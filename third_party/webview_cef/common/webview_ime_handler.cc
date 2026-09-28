#include "webview_handler.h"
#include "include/base/cef_callback.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

void WebviewHandler::setNativeCallback(std::function<void(cef_ime::Update)> callback) {
  // Installed before CEF initialization; callback uses a weak mailbox and needs
  // no cross-thread teardown mutation.
  native_callback_ = std::move(callback);
}

void WebviewHandler::nativeFocus(int browser, uint64_t epoch) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::nativeFocus, this, browser, epoch));
    return;
  }
  if (epoch < native_epoch_) return;
  auto old = browser_map_.find(native_browser_);
  if (old != browser_map_.end() && old->second.browser) {
    old->second.browser->GetHost()->ImeCancelComposition();
    old->second.browser->GetHost()->SetFocus(false);
    old->second.wants_focus = false;
  }
  native_browser_ = browser; native_epoch_ = epoch; native_composition_.composing = false;
  if (native_callback_) native_callback_({browser, epoch, false, false, {}, 1});
  native_composition_.cursor = 0;
  auto it = browser_map_.find(browser);
  if (it == browser_map_.end() || !it->second.browser) return;
  it->second.native_editable = false;
  setClientFocus(browser, true);
  std::vector<CefString> frames;
  it->second.browser->GetFrameIdentifiers(frames);
  for (const auto& id : frames) {
    auto frame = it->second.browser->GetFrameByIdentifier(id);
    if (!frame) continue;
    auto msg = CefProcessMessage::Create("webview.cef.ime.epoch");
    msg->GetArgumentList()->SetString(0, std::to_string(epoch));
    frame->SendProcessMessage(PID_RENDERER, msg);
  }
}

void WebviewHandler::nativeGeometry(int browser, cef_ime::Geometry geometry) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::nativeGeometry, this, browser, geometry));
    return;
  }
  auto it = browser_map_.find(browser);
  if (it == browser_map_.end() || !it->second.browser) return;
  it->second.geometry = geometry;
  it->second.dpi = static_cast<float>(geometry.dpi);
  it->second.browser->GetHost()->NotifyScreenInfoChanged();
}

void WebviewHandler::nativeInput(int browser, uint64_t epoch, cef_ime::Input kind,
                               std::wstring text, int cursor) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::nativeInput, this,
                                     browser, epoch, kind, std::move(text), cursor));
    return;
  }
  if (!cef_ime::IsCurrent(browser, epoch, native_browser_, native_epoch_)) return;
  auto it = browser_map_.find(browser);
  if (it == browser_map_.end() || !it->second.browser) return;
  native_composition_.Apply(kind, static_cast<int>(text.size()), cursor);
  auto host = it->second.browser->GetHost();
  CefString value; value.FromWString(text);
  if (kind == cef_ime::Input::Cancel) {
    host->ImeCancelComposition(); native_composition_.composing = false;
  } else if (kind == cef_ime::Input::Commit) {
    host->ImeCommitText(value, CefRange(UINT32_MAX, UINT32_MAX), 0);
    native_composition_.composing = false;
    refreshNativeCaret(it->second.browser, 8);
  } else {
    if (text.empty()) { host->ImeCancelComposition(); refreshNativeCaret(it->second.browser, 4); return; }
    CefCompositionUnderline line;
    line.range = CefRange(0, static_cast<uint32_t>(text.size()));
    line.color = ColorUNDERLINE; line.background_color = ColorBKCOLOR;
    line.thick = false; line.style = CEF_CUS_SOLID;
    host->ImeSetComposition(value, {line}, CefRange(UINT32_MAX, UINT32_MAX),
                           CefRange(native_composition_.cursor, native_composition_.cursor));
    refreshNativeCaret(it->second.browser, 8);
  }
}

void WebviewHandler::refreshNativeCaret(CefRefPtr<CefBrowser> browser, int frames) {
  if (!browser) return;
  std::vector<CefString> frames_ids;
  browser->GetFrameIdentifiers(frames_ids);
  for (const auto& id : frames_ids) {
    auto frame = browser->GetFrameByIdentifier(id);
    if (!frame) continue;
    auto msg = CefProcessMessage::Create("webview.cef.ime.refresh");
    msg->GetArgumentList()->SetInt(0, frames);
    frame->SendProcessMessage(PID_RENDERER, msg);
  }
}

void WebviewHandler::nativeKey(int browser, uint64_t epoch, CefKeyEvent event) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::nativeKey, this, browser, epoch, event));
    return;
  }
  if (!cef_ime::IsCurrent(browser, epoch, native_browser_, native_epoch_)) return;
  auto it = browser_map_.find(browser);
  if (it != browser_map_.end() && it->second.browser) it->second.browser->GetHost()->SendKeyEvent(event);
}

void WebviewHandler::publishNativeCaret(CefRefPtr<CefBrowser> browser, const CefRect& rect) {
  if (native_callback_) native_callback_({browser->GetIdentifier(), native_epoch_, true, true,
      {double(rect.x), double(rect.y), double(rect.width), double(rect.height)}});
}

bool WebviewHandler::GetScreenPoint(CefRefPtr<CefBrowser> browser, int x, int y,
                                  int& screen_x, int& screen_y) {
  const auto it = browser_map_.find(browser->GetIdentifier());
  if (it == browser_map_.end()) return false;
  const auto& g = it->second.geometry;
  screen_x = g.screen_x + static_cast<int>(std::lround((g.a*x + g.c*y + g.tx)*g.dpi));
  screen_y = g.screen_y + static_cast<int>(std::lround((g.b*x + g.d*y + g.ty)*g.dpi));
  return true;
}
