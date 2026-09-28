#pragma once
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commctrl.h>
#include <deque>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <set>
#include "webview_handler.h"

namespace webview_cef {
class WindowsIme {
 public:
  WindowsIme(HWND hwnd, CefRefPtr<WebviewHandler> handler);
  ~WindowsIme();
  bool HandleMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
 private:
  struct Mailbox { std::mutex mutex; std::deque<cef_ime::Update> updates; HWND hwnd = nullptr; };
  static LRESULT CALLBACK Subclass(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
  LRESULT Message(UINT, WPARAM, LPARAM);
  void Focus(int browser);
  void Cancel();
  void Position();
  void RefreshGeometry();
  void Drain();
  HWND hwnd_;
  HWND parent_ = nullptr;
  CefRefPtr<WebviewHandler> handler_;
  std::shared_ptr<Mailbox> mailbox_;
  std::unordered_map<int, cef_ime::Geometry> geometry_;
  int active_ = -1;
  uint64_t epoch_ = 0;
  bool editable_ = false, composing_ = false, caret_created_ = false, has_rect_ = false;
  bool trace_ = false;
  bool click_anchor_ = false;
  double last_client_x_ = 0, last_client_y_ = 0, last_client_height_ = 0;
  double last_screen_x_ = 0, last_screen_y_ = 0;
  int diagnostics_[5] = {};
  std::set<WPARAM> ime_keys_;
  cef_ime::Rect rect_;
};
}
