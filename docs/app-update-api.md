# KNcard 无线更新接口约定

客户端进入主界面后、回到前台时，以及“我的 → 应用更新 → 检查更新”会请求：

```text
GET /api/v1/app/update?platform=android&version=1.0.0&build=1
```

建议返回没有更新时：

```json
{
  "available": false
}
```

有更新时返回：

```json
{
  "available": true,
  "versionName": "1.1.0",
  "buildNumber": 2,
  "mandatory": false,
  "notes": "修复同步和复习页面问题。",
  "downloadUrl": "https://example.com/releases/kncard-1.1.0.apk",
  "sha256": "64 位十六进制 SHA-256",
  "sizeBytes": 12345678,
  "releaseUrl": "https://example.com/releases/1.1.0"
}
```

也支持把 Android 产物放在 `android` 字段中，或把结果包在 `update` / `data` 字段中。客户端要求更新包同时提供有效的 HTTPS 地址和 64 位十六进制 SHA-256；缺少校验值时不会下载或安装。客户端会校验文件大小和 SHA-256，然后调用 Android 系统安装器，不会静默安装。正式环境不要使用 HTTP 更新地址。

## 关于增量包

返回体可以预留：

```json
{
  "patch": {
    "url": "https://example.com/releases/kncard-1-to-2.bsdiff",
    "sha256": "...",
    "sizeBytes": 1234,
    "fromBuildNumber": 1
  }
}
```

当前客户端会读取并保留这些字段，但仍以完整 APK 安全回退。自托管 APK 的差分合并需要服务端生成 bsdiff/同类补丁，并在 Android 原生层增加受签名保护的补丁合并器；不能直接把差分文件交给系统安装器。若通过 Google Play 发布，Play 会在后台自动处理设备适配和差分传输，建议优先使用 Play 的应用内更新能力。

## 平台限制

- Android：支持下载、校验并唤起系统安装器；首次安装可能需要用户允许“安装未知应用”。
- iOS：不能从自有服务器直接安装更新，必须通过 App Store、TestFlight 或企业签名渠道。
- Flutter/Dart 代码不能在商店版本中绕过签名直接热替换；若需要真正的热更新，需要单独评估合规的受限脚本/资源更新方案。
