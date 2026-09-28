#include "webview_ime_win.h"
#include "webview_cef_keyevent.h"
#include <imm.h>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
#include <cwctype>

namespace webview_cef {
namespace {
constexpr UINT kUpdate = WM_APP + 0x4CE;
constexpr UINT_PTR kSubclass = 0xCEF149;
int Int(const flutter::EncodableValue& v) {
  if (auto n = std::get_if<int32_t>(&v)) return *n;
  if (auto n = std::get_if<int64_t>(&v)) return static_cast<int>(*n);
  return -1;
}
std::wstring ReadString(HIMC imc, DWORD flag) {
  const LONG bytes = ImmGetCompositionStringW(imc, flag, nullptr, 0);
  if (bytes <= 0 || bytes % sizeof(wchar_t)) return {};
  std::wstring text(static_cast<size_t>(bytes)/sizeof(wchar_t), L'\0');
  if (ImmGetCompositionStringW(imc, flag, text.data(), bytes) < 0) return {};
  return text;
}
struct CandidateWindow {
  std::wstring title;
  std::wstring klass;
  RECT rect = {};
};
BOOL CALLBACK EnumCandidateWindows(HWND hwnd, LPARAM lp) {
  if (!IsWindowVisible(hwnd)) return TRUE;
  wchar_t klass[256] = {};
  wchar_t title[256] = {};
  GetClassNameW(hwnd, klass, 256);
  GetWindowTextW(hwnd, title, 256);
  std::wstring k = klass;
  std::wstring t = title;
  auto lower = [](std::wstring s) {
    for (auto& c : s) c = static_cast<wchar_t>(towlower(c));
    return s;
  };
  const auto lk = lower(k);
  const auto lt = lower(t);
  if (lk.find(L"candidate") == std::wstring::npos &&
      lk.find(L"ime") == std::wstring::npos &&
      lt.find(L"candidate") == std::wstring::npos &&
      lt.find(L"ime") == std::wstring::npos) {
    return TRUE;
  }
  RECT r = {};
  if (!GetWindowRect(hwnd, &r) || r.right <= r.left || r.bottom <= r.top) return TRUE;
  auto* out = reinterpret_cast<std::vector<CandidateWindow>*>(lp);
  out->push_back({t, k, r});
  return TRUE;
}
std::string Narrow(const std::wstring& s) {
  if (s.empty()) return {};
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (bytes <= 1) return {};
  std::string out(static_cast<size_t>(bytes - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, out.data(), bytes, nullptr, nullptr);
  return out;
}
}
WindowsIme::WindowsIme(HWND hwnd, CefRefPtr<WebviewHandler> handler)
    : hwnd_(hwnd), handler_(handler), mailbox_(std::make_shared<Mailbox>()) {
  mailbox_->hwnd = hwnd;
  wchar_t flag[2] = {};
  trace_ = GetEnvironmentVariableW(L"WEBVIEW_CEF_IME_TRACE", flag, 2) == 1 && flag[0] == L'1';
  std::weak_ptr<Mailbox> weak = mailbox_;
  handler_->setNativeCallback([weak](cef_ime::Update update) {
    if (auto box = weak.lock()) {
      std::lock_guard<std::mutex> lock(box->mutex);
      if (!box->hwnd) return;
      box->updates.push_back(update);
      PostMessage(box->hwnd, kUpdate, 0, 0);
    }
  });
  SetWindowSubclass(hwnd_, Subclass, kSubclass, reinterpret_cast<DWORD_PTR>(this));
}
WindowsIme::~WindowsIme() {
  Focus(-1);
  RemoveWindowSubclass(hwnd_, Subclass, kSubclass);
  if (parent_) RemoveWindowSubclass(parent_, Subclass, kSubclass);
  std::lock_guard<std::mutex> lock(mailbox_->mutex);
  mailbox_->hwnd = nullptr; mailbox_->updates.clear();
}
void WindowsIme::Cancel() {
  if (composing_) {
    HIMC imc = ImmGetContext(hwnd_);
    // Clear first: ImmNotifyIME can synchronously re-enter the subclass.
    composing_ = false;
    if (imc) { ImmNotifyIME(imc, NI_COMPOSITIONSTR, CPS_CANCEL, 0); ImmReleaseContext(hwnd_, imc); }
    handler_->nativeInput(active_, epoch_, cef_ime::Input::Cancel);
  }
  if (caret_created_) { DestroyCaret(); caret_created_ = false; }
}
void WindowsIme::Focus(int browser) {
  Cancel();
  active_ = browser; ++epoch_; editable_ = false; has_rect_ = false;
  click_anchor_ = false;
  ime_keys_.clear();
  handler_->nativeFocus(active_, epoch_);
}
void WindowsIme::RefreshGeometry() {
  // Flutter reparents its view after plugin registration.
  const HWND root = GetAncestor(hwnd_, GA_ROOT);
  if (root != hwnd_ && root != parent_) {
    if (parent_) RemoveWindowSubclass(parent_, Subclass, kSubclass);
    parent_ = root;
    SetWindowSubclass(parent_, Subclass, kSubclass, reinterpret_cast<DWORD_PTR>(this));
  }
  POINT origin = {0, 0}; ClientToScreen(hwnd_, &origin);
  MONITORINFO info = {}; info.cbSize = sizeof(info);
  GetMonitorInfo(MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST), &info);
  for (auto& entry : geometry_) {
    auto& g = entry.second;
    g.screen_x = origin.x; g.screen_y = origin.y;
    g.dpi = GetDpiForWindow(hwnd_) / 96.0;
    g.monitor = {double(info.rcMonitor.left), double(info.rcMonitor.top),
                 double(info.rcMonitor.right-info.rcMonitor.left), double(info.rcMonitor.bottom-info.rcMonitor.top)};
    g.work = {double(info.rcWork.left), double(info.rcWork.top),
              double(info.rcWork.right-info.rcWork.left), double(info.rcWork.bottom-info.rcWork.top)};
    handler_->nativeGeometry(entry.first, g);
  }
  Position();
}
void WindowsIme::Position() {
  if (!editable_ || !has_rect_ || GetFocus() != hwnd_) return;
  const auto it = geometry_.find(active_);
  if (it == geometry_.end()) return;
  const auto r = cef_ime::Transform(rect_, it->second);
  last_client_x_ = r.x; last_client_y_ = r.y; last_client_height_ = r.height;
  last_screen_x_ = it->second.screen_x + r.x;
  last_screen_y_ = it->second.screen_y + r.y;
  if (!caret_created_) caret_created_ = CreateCaret(hwnd_, nullptr, 1, std::max(1, int(r.height))) != FALSE;
  if (caret_created_) SetCaretPos(int(r.x), int(r.y));
  HIMC imc = ImmGetContext(hwnd_);
  if (!imc) return;
  CANDIDATEFORM position = {0, CFS_CANDIDATEPOS, {LONG(r.x), LONG(r.y+r.height)}, {0,0,0,0}};
  ImmSetCandidateWindow(imc, &position);
  CANDIDATEFORM exclude = {0, CFS_EXCLUDE, {LONG(r.x), LONG(r.y+r.height)},
      {LONG(r.x), LONG(r.y), LONG(r.x+r.width), LONG(r.y+r.height)}};
  ImmSetCandidateWindow(imc, &exclude);
  COMPOSITIONFORM composition = {CFS_POINT, {LONG(r.x), LONG(r.y)}, {0,0,0,0}};
  ImmSetCompositionWindow(imc, &composition);
  ImmReleaseContext(hwnd_, imc);
  if (trace_) {
    char line[200]; std::snprintf(line, sizeof(line), "[cef-ime] browser=%d epoch=%llu dpi=%.2f rect=%.0f,%.0f,%.0f,%.0f\n",
      active_, static_cast<unsigned long long>(epoch_), it->second.dpi, r.x, r.y, r.width, r.height);
    OutputDebugStringA(line);
  }
}
void WindowsIme::Drain() {
  std::deque<cef_ime::Update> updates;
  { std::lock_guard<std::mutex> lock(mailbox_->mutex); updates.swap(mailbox_->updates); }
  for (const auto& u : updates) {
    if (u.diagnostic > 0 && u.diagnostic < 5) { ++diagnostics_[u.diagnostic]; continue; }
    if (!cef_ime::IsCurrent(u.browser, u.epoch, active_, epoch_)) continue;
    if (u.fallback) {
      if (editable_) Cancel();
      if (click_anchor_) { editable_ = u.editable; continue; }
      has_rect_ = false;
    }
    if (!u.editable) { Cancel(); has_rect_ = false; }
    editable_ = u.editable;
    if (u.has_rect && std::isfinite(u.rect.x) && std::isfinite(u.rect.y) &&
        std::isfinite(u.rect.height) && u.rect.height > 0) {
      rect_ = u.rect; has_rect_ = true;
      if (!u.fallback) click_anchor_ = false;
    }
  }
  Position();
}
bool WindowsIme::HandleMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& name = call.method_name();
  if (name == "imeDiagnostics" && trace_) {
    Drain();
    flutter::EncodableMap values;
    values[flutter::EncodableValue("browser")] = flutter::EncodableValue(active_);
    values[flutter::EncodableValue("epoch")] = flutter::EncodableValue(static_cast<int64_t>(epoch_));
    values[flutter::EncodableValue("editable")] = flutter::EncodableValue(editable_);
    values[flutter::EncodableValue("composing")] = flutter::EncodableValue(composing_);
    values[flutter::EncodableValue("hasRect")] = flutter::EncodableValue(has_rect_);
    values[flutter::EncodableValue("x")] = flutter::EncodableValue(rect_.x);
    values[flutter::EncodableValue("y")] = flutter::EncodableValue(rect_.y);
    values[flutter::EncodableValue("height")] = flutter::EncodableValue(rect_.height);
    values[flutter::EncodableValue("clientX")] = flutter::EncodableValue(last_client_x_);
    values[flutter::EncodableValue("clientY")] = flutter::EncodableValue(last_client_y_);
    values[flutter::EncodableValue("clientHeight")] = flutter::EncodableValue(last_client_height_);
    values[flutter::EncodableValue("screenX")] = flutter::EncodableValue(last_screen_x_);
    values[flutter::EncodableValue("screenY")] = flutter::EncodableValue(last_screen_y_);
    values[flutter::EncodableValue("focusApplied")] = flutter::EncodableValue(diagnostics_[1]);
    values[flutter::EncodableValue("contextsReady")] = flutter::EncodableValue(diagnostics_[2]);
    values[flutter::EncodableValue("geometryMessages")] = flutter::EncodableValue(diagnostics_[3]);
    values[flutter::EncodableValue("loadsCompleted")] = flutter::EncodableValue(diagnostics_[4]);
    result->Success(flutter::EncodableValue(values)); return true;
  }
  if (name == "imeCandidateWindows") {
    std::vector<CandidateWindow> windows;
    EnumWindows(EnumCandidateWindows, reinterpret_cast<LPARAM>(&windows));
    flutter::EncodableList list;
    for (const auto& w : windows) {
      flutter::EncodableMap item;
      item[flutter::EncodableValue("class")] = flutter::EncodableValue(Narrow(w.klass));
      item[flutter::EncodableValue("title")] = flutter::EncodableValue(Narrow(w.title));
      item[flutter::EncodableValue("left")] = flutter::EncodableValue(static_cast<int32_t>(w.rect.left));
      item[flutter::EncodableValue("top")] = flutter::EncodableValue(static_cast<int32_t>(w.rect.top));
      item[flutter::EncodableValue("right")] = flutter::EncodableValue(static_cast<int32_t>(w.rect.right));
      item[flutter::EncodableValue("bottom")] = flutter::EncodableValue(static_cast<int32_t>(w.rect.bottom));
      list.push_back(flutter::EncodableValue(item));
    }
    result->Success(flutter::EncodableValue(list)); return true;
  }
  const auto* args = call.arguments() ? std::get_if<flutter::EncodableList>(call.arguments()) : nullptr;
  if (name == "imeGeometry") {
    if (!args || args->size() != 10) { result->Error("geometry", "Expected browser and nine doubles"); return true; }
    double v[9];
    for (int i=0; i<9; ++i) {
      const auto* n = std::get_if<double>(&(*args)[i+1]);
      if (!n || !std::isfinite(*n)) { result->Error("geometry", "Invalid geometry"); return true; }
      v[i] = *n;
    }
    if (v[6] <= 0) { result->Error("geometry", "Invalid DPI"); return true; }
    auto& g = geometry_[Int((*args)[0])];
    g.a=v[0]; g.b=v[1]; g.c=v[2]; g.d=v[3]; g.tx=v[4]; g.ty=v[5]; g.dpi=v[6];
    RefreshGeometry(); result->Success(); return true;
  }
  if (name == "setClientFocus" && args && args->size() == 2) {
    int id = Int((*args)[0]); const auto* focused = std::get_if<bool>(&(*args)[1]);
    if (focused && *focused && active_ != id) Focus(id);
    else if (focused && !*focused && active_ == id) Focus(-1);
    result->Success(); return true;
  }
  if (name == "cursorClickDown" && args && args->size() == 3) {
    int id = Int((*args)[0]);
    // A new click starts a new target generation, even within one browser.
    Focus(id);
    rect_ = {double(Int((*args)[1])), double(Int((*args)[2])), 1, 20}; has_rect_ = true;
    click_anchor_ = true;
  }
  if (name == "close" && call.arguments()) {
    const int id = Int(*call.arguments());
    if (active_ == id) Focus(-1);
    geometry_.erase(id);
  }
  if ((name == "loadUrl" && args && !args->empty() && Int((*args)[0]) == active_) ||
      ((name == "reload" || name == "goBack" || name == "goForward") &&
       call.arguments() && Int(*call.arguments()) == active_)) Focus(active_);
  return false;
}
LRESULT CALLBACK WindowsIme::Subclass(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR data) {
  auto* self = reinterpret_cast<WindowsIme*>(data);
  if (hwnd != self->hwnd_) {
    const auto result = DefSubclassProc(hwnd, msg, wp, lp);
    if (msg == WM_WINDOWPOSCHANGED || msg == WM_DPICHANGED) self->RefreshGeometry();
    return result;
  }
  return self->Message(msg, wp, lp);
}
LRESULT WindowsIme::Message(UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == kUpdate) { Drain(); return 0; }
  if (msg == WM_KILLFOCUS) { Cancel(); has_rect_ = false; }
  if (msg == WM_SETFOCUS && active_ >= 0) Focus(active_);
  if (msg == WM_WINDOWPOSCHANGED || msg == WM_DPICHANGED || msg == WM_DPICHANGED_AFTERPARENT) RefreshGeometry();
  if (msg == WM_INPUTLANGCHANGE) { Cancel(); Position(); }
  if (active_ >= 0 && GetFocus() == hwnd_) {
    if (editable_) {
      switch (msg) {
        case WM_IME_SETCONTEXT: return DefSubclassProc(hwnd_, msg, wp, lp & ~ISC_SHOWUICOMPOSITIONWINDOW);
        case WM_IME_STARTCOMPOSITION:
          composing_ = true;
          // A preceding Flutter text client may have destroyed the system
          // caret asynchronously. Re-establish it for this native composition.
          if (caret_created_) DestroyCaret();
          caret_created_ = false;
          Position(); return 0;
        case WM_IME_COMPOSITION: {
          HIMC imc = ImmGetContext(hwnd_);
          if (imc) {
            if (lp & GCS_RESULTSTR) {
              handler_->nativeInput(active_, epoch_, cef_ime::Input::Commit, ReadString(imc, GCS_RESULTSTR));
            }
            if (lp & (GCS_COMPSTR | GCS_CURSORPOS | GCS_COMPATTR)) {
              auto text = ReadString(imc, GCS_COMPSTR);
              int cursor = static_cast<int>(ImmGetCompositionStringW(imc, GCS_CURSORPOS, nullptr, 0));
              handler_->nativeInput(active_, epoch_, cef_ime::Input::Compose, text, cursor);
            }
            if (lp == 0) handler_->nativeInput(active_, epoch_, cef_ime::Input::Cancel);
            ImmReleaseContext(hwnd_, imc);
          }
          Position(); return 0;
        }
        case WM_IME_ENDCOMPOSITION:
          composing_ = false;
          handler_->nativeInput(active_, epoch_, cef_ime::Input::Cancel);
          return 0;
        case WM_IME_CHAR: return 0;
      }
    }
    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN || msg == WM_KEYUP || msg == WM_SYSKEYUP ||
        msg == WM_CHAR || msg == WM_SYSCHAR) {
      const bool up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
      const bool captured = composing_ || wp == VK_PROCESSKEY || ime_keys_.count(wp) != 0;
      if (captured) {
        if (up) ime_keys_.erase(wp); else if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) ime_keys_.insert(wp);
      } else {
        handler_->nativeKey(active_, epoch_, getCefKeyEvent(msg, wp, lp));
      }
      // Flutter still needs hardware key bookkeeping, but has no text client
      // for this browser. IME messages above are exclusively native-owned.
    }
  }
  return DefSubclassProc(hwnd_, msg, wp, lp);
}
}
