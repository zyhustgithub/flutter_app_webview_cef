# Local Windows IME fork

Base: `webview_cef` 0.6.2, https://pub.dev/packages/webview_cef/versions/0.6.2
Upstream: https://github.com/hlwhl/webview_cef
CEF remains 149.0.4 / Chromium 149.0.7827.156. The upstream LICENSE is retained.

This source was imported from the installed 0.6.2 package. Its previous local
Windows TextInput passthrough patch was replaced here. The global Pub cache is
not modified. The downloaded CEF distribution is excluded from version control.

Windows changes:

- `windows/webview_ime_win.*` owns IMM messages, candidate positioning, system
  caret, active browser and focus generation on the HWND thread. CEF callbacks
  use a weak mailbox; no heap pointers are owned by posted Win32 messages.
- `common/webview_ime_handler.cc` marshals native focus, geometry, composition
  and keyboard operations to CEF UI. Input tasks contain an explicit browser ID
  and generation. Preedit, commit and cancel are distinct operations.
- `common/ime_caret.js` runs in each renderer context. It reports numeric caret
  geometry, normalizes nested iframe positions through parent relays, handles
  input/textarea mirrors, contenteditable selections, scrolling and page zoom.
  Password mirrors contain masking characters. No entered text is sent through
  the geometry bridge or logged by the IME diagnostics.
- CEF view coordinates and Flutter logical coordinates are converted to HWND
  client pixels once. Screen point requests additionally apply ClientToScreen.
  Screen information and notifications include monitor and work-area bounds.
- Flutter Windows widgets no longer attach a competing TextInput client. Their
  affine transform and size are refreshed on scheduled frames without forcing
  an idle rendering loop. Non-Windows text-input behavior remains upstream.
- Optional `WEBVIEW_CEF_ROOT` CMake cache path reuses a prepared distribution.
  Leaving it empty uses the upstream download workflow.

References:

- https://github.com/chromiumembedded/cef/blob/master/tests/cefclient/browser/osr_ime_handler_win.cc
- https://github.com/chromiumembedded/cef/blob/master/include/cef_render_handler.h
- https://github.com/chromiumembedded/cef/issues/4070
- https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immsetcandidatewindow

Do not reapply `patches/webview_cef+0.6.2-ime-position.patch`: it describes the
retired global-cache patch and has been removed from the project workflow.
