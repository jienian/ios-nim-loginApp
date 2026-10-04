# ios-nim-loginApp

一个用 **Swift + SwiftUI** 写的 iOS 登录交互逻辑示例 App，重点不在 UI 花哨，而在把登录这条链路做完整：

输入校验 → 状态管理 → 模拟网络请求 → 成功/失败处理 → 登录态保持 → 退出登录。

## 功能

- 账号输入：支持邮箱 / 手机号，自动判断类型并校验格式
- 密码输入：显示/隐藏切换、长度校验、注册时密码强度提示
- 实时校验：输入时提示错误，错误信息贴在输入框下方，不弹窗打断
- 登录按钮状态：`不可点（未填完）→ 可点 → 加载中（转圈、防重复点击）→ 成功/失败`
- 模拟登录接口：`MockAuthService` 延迟 1.2 秒模拟网络
  - 演示账号：`demo@nim.app` / `123456`
  - 密码不对会返回明确错误；演示账号以外、格式正确的账号也可登录成功（方便体验流程）
- 注册模式：登录/注册切换，含确认密码一致性校验
- 记住我：勾选后下次自动填充账号
- 登录态保持：登录成功后保存 mock token，杀掉 App 重开仍是登录状态
- 主页：显示当前用户、登录时间，支持退出登录
- 忘记密码：底部弹层，校验邮箱后提示已发送重置邮件（模拟）
- Face ID 按钮：入口和交互占位，点击会提示演示模式未启用生物识别

## 技术结构（MVVM）

```
NimLoginApp/
├── NimLoginAppApp.swift        // App 入口
├── ContentView.swift           // 根据登录态切换 登录页 / 主页
├── Models/
│   └── User.swift              // User、AuthSession
├── Services/
│   └── AuthService.swift       // AuthService 协议 + Mock 实现，真接口替换这里即可
├── ViewModels/
│   └── AuthViewModel.swift     // 登录交互逻辑核心：校验、状态、异步登录
├── Views/
│   ├── LoginView.swift         // 登录/注册页
│   ├── HomeView.swift          // 登录成功后的主页
│   └── Components/
│       ├── InputField.swift    // 带错误提示的输入框组件
│       └── PrimaryButton.swift // 带 loading 状态的主按钮
└── Utils/
    └── Validators.swift        // 邮箱/手机号/密码校验，可单测
NimLoginAppTests/
├── ValidatorsTests.swift
└── AuthViewModelTests.swift
```

把 `MockAuthService` 换成真实接口时，只需要实现 `AuthService` 协议（`login` / `register`），`ViewModel` 和 `View` 不用改。

## 运行

1. 用 Xcode 15+ 打开 `NimLoginApp.xcodeproj`
2. 选 iPhone 模拟器，直接 Run
3. 用演示账号登录：`demo@nim.app` / `123456`
   - 故意输错密码可以看到失败状态和错误提示

最低系统：iOS 17.0

## 测试

Xcode 里按 `Cmd + U` 运行单测，覆盖了校验规则和登录成功/失败/重复提交等核心逻辑。
