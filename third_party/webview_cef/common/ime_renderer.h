#pragma once
#include "include/cef_v8.h"
#include "include/cef_frame.h"
#include "ime_caret_script.h"

class ImeRectReporter : public CefV8Handler {
 public:
  bool Execute(const CefString&, CefRefPtr<CefV8Value>, const CefV8ValueList& args,
               CefRefPtr<CefV8Value>&, CefString&) override {
    if (args.size() != 6 || !args[0]->IsString() || !args[1]->IsBool()) return true;
    auto context = CefV8Context::GetCurrentContext();
    if (!context) return true;
    auto msg = CefProcessMessage::Create("webview.cef.ime.rect");
    auto values = msg->GetArgumentList();
    values->SetString(0, args[0]->GetStringValue());
    values->SetBool(1, args[1]->GetBoolValue());
    for (size_t i = 2; i < 6; ++i) values->SetDouble(i, args[i]->GetDoubleValue());
    context->GetFrame()->SendProcessMessage(PID_BROWSER, msg);
    return true;
  }
 private:
  IMPLEMENT_REFCOUNTING(ImeRectReporter);
};
inline void InstallImeReporter(CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) {
  context->GetGlobal()->SetValue("__cefImeReport", CefV8Value::CreateFunction("report", new ImeRectReporter), V8_PROPERTY_ATTRIBUTE_NONE);
  CefRefPtr<CefV8Value> result;
  CefRefPtr<CefV8Exception> error;
  context->Eval(kImeCaretScript, "webview-cef://ime-caret", 0, result, error);
  frame->SendProcessMessage(PID_BROWSER, CefProcessMessage::Create("webview.cef.ime.ready"));
}
