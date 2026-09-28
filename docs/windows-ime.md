# Windows 输入法维护与验收

## 构建

项目通过 `pubspec.yaml` 的 path 依赖使用 `third_party/webview_cef`。执行
`flutter pub get` 即可，无需 npm postinstall，也不要修改 Pub 缓存。

```powershell
flutter pub get
flutter build windows --debug
flutter build windows --release
```

第一次构建默认下载固定版本的 CEF。已有完整 CEF 149 标准发行包时，可以在
Flutter 生成 Windows 构建目录后配置 `WEBVIEW_CEF_ROOT`，然后重新构建：

```powershell
cmake -S windows -B build/windows/x64 -DWEBVIEW_CEF_ROOT="D:/deps/cef149"
flutter build windows --debug
```

该路径仅保存在本机 CMake 缓存。清理构建目录后需要重新设置；不要把机器专用
路径写入项目源码。原生 C++ 改动必须完整重编译，热重载不会更新插件 DLL。
项目原有的软件 OSR 配置保留；本次没有切换 GPU 渲染方式。

## 复现页面

首页选择“Windows 输入法回归测试”，使用微软拼音。

| 场景 | 检查内容 |
| --- | --- |
| 首次点击单行输入框 | 输入拼音时，候选框在当前光标附近，不能固定在窗口左上角 |
| 多行输入框 | 第一行、中间行、末行及框内滚动后，候选框随光标移动 |
| 富文本、滚动容器、iframe | 页面滚动、父容器偏移和 frame 边框计入定位 |
| 内嵌、弹窗、双 WebView | 不把上一目标的组合文本或候选框留给新目标 |
| Flutter 输入框与网页往返 | 双方都能输入；关闭弹窗、刷新、导航时不提交残留拼音 |
| 100/125/150/200% 缩放 | 光标定位与鼠标命中一致；不出现成比例的偏移 |
| 跨不同 DPI 显示器移动 | 窗口移动和 DPI 改变后更新候选位置，包含负屏幕坐标 |

每种布局至少检查：拼音预编辑、空格/数字选词、回车、Esc、退格删空、英文、
中英文切换、复制粘贴、Tab 和方向键。屏幕边缘处允许输入法自行向上避让。

## 自动验证

```powershell
flutter test
dart analyze lib test third_party/webview_cef/lib
cmake -S test/native -B build/ime-tests -G "Visual Studio 17 2022" -A x64
cmake --build build/ime-tests --config Debug
ctest --test-dir build/ime-tests -C Debug --output-on-failure
```

原生测试覆盖非整数 DPI、控件变换、换行与末尾光标、无字符矩形、过期焦点
代次、预编辑更新、提交、取消及删空。真实 CEF 冒烟入口为
`tools/ime_smoke.dart`，需要启用下述诊断开关后构建运行，结果写入
`build/ime_smoke.json`。完成测试后重新构建默认 `lib/main.dart` 入口。

```powershell
$env:WEBVIEW_CEF_IME_TRACE = '1'
flutter build windows --debug -t tools/ime_smoke.dart
$smoke = Start-Process -FilePath ./build/windows/x64/runner/Debug/webview_cef_app.exe -WorkingDirectory $PWD -WindowStyle Hidden -PassThru
$smoke.WaitForExit()
Get-Content build/ime_smoke.json
Remove-Item Env:WEBVIEW_CEF_IME_TRACE
flutter build windows --debug -t lib/main.dart
```

后台冒烟入口通过 controller 显式切换原生输入所有权，避免桌面窗口激活状态
干扰结果；它验证 CEF 渲染器与插件消息链路，不能替代真实点击和微软拼音验收。
测试页使用打包的 HTML 文件地址，避免初始 data URL 停留在空白页。

## 诊断

```powershell
$env:WEBVIEW_CEF_IME_TRACE = '1'
flutter run -d windows
```

诊断默认关闭。启用后使用 Windows 调试输出记录 browserId、焦点代次、DPI 和
坐标；`imeDiagnostics` 内部通道提供几何与生命周期计数，不返回输入内容。
取消环境变量可关闭诊断。不要把“自动化测试通过”视为已验证微软拼音的系统
候选窗口；该窗口以及多显示器避让行为需要实际人工验收。
