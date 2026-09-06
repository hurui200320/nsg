# nsg - 尼康智能 GPS（安卓完整实现）

> English README: [README.md](README.md)

一个 Nikon SnapBridge 的替代方案：通过蓝牙 smart-device 模式，把手机的 GPS 位置持续注入尼康 Z 系列相机，让照片自动带上地理坐标。

本项目在 [hurui200320/nsg](https://github.com/hurui200320/nsg) 的基础上，**完成了安卓端的完整实现**（原作者只提供了安卓 PoC 与 ESP32 方案）。配对协议逆向成果来自 [gkoh/furble](https://github.com/gkoh/furble)。

> 背景：国内销售的相机被强制禁用了内置 GPS，SnapBridge 又存在不稳定、耗电高等问题。这个项目让一台闲置的安卓手机变成相机的专用 GPS 设备。

- 中文版：[**使用教程**](README.zh-CN.md#%E4%BD%BF%E7%94%A8%E6%95%99%E7%A8%8B)
- English: [**Usage Tutorial**](README.md#usage)

---

## 功能详解

### 1. SnapBridge 设备标识自动破解（核心特性）

相机一旦和 SnapBridge 配对过，就只接受 SnapBridge 的「设备标识」。本项目通过数学反解，可以自动恢复该标识，让本 App **与 SnapBridge 无缝切换，无需删除任何配对记录**。

破解算法单独维护在独立项目 [snapbridge-id-extractor](https://github.com/HowenXu/snapbridge-id-extractor) 中（含完整原理说明与代码）。本 App 在「配对新相机」时若检测到相机已有配对记录，会自动调用该算法完成破解并连接（日志区会实时输出进度）。

### 2. 控制器名称自动伪装

App 会自动生成与 SnapBridge 相同格式的控制器名称（`Android_机型_四位随机数`），相机端显示的名字风格与 SnapBridge 一致。

### 3. 真实 GPS 注入

- 连接相机后自动开启定位（GPS + 网络定位），实时把经纬度/精度打包成尼康 GEO 载荷写入相机；
- 低功耗策略：静止且近期已发送时跳过；30 秒兜底保活；
- 断开连接后自动关闭定位，省电。

### 4. 后台运行与低耗电

- 前台服务 + `START_STICKY`，任务移除后自动重启；
- 启动时自动检查电池优化豁免并主动申请（保证后台存活）；
- 连接成功后可保持后台运行，低频率发送 GPS。

### 5. 已保存相机管理

- 支持保存多台相机；列表支持「连接」「自动提取标识」「设为默认」「删除」；
- 多台相机时可设置「启动时默认连接」的那一台；
- 启动自动连接时，只要服务仍在运行，App 会持续等待所选/默认相机出现并自动重连。

### 6. 界面与本地化

- 主界面分状态区 / 日志区 / 操作区，日志可滚动查看；
- 右上角三点菜单进入「高级设置」页（相机端设备名、固定设备标识）；
- 连接过程中按钮显示加载动画；
- 自动跟随系统语言：中文系统显示中文，其他语言显示英文。

### 7. 兼容性

- 最低支持 **Android 7（API 24）**，可放心使用闲置老手机；
- 已实测机型：**华为 Mate 40 Pro**、**华为 MatePad Pro 10.8**；
- 相机实测：**仅实测尼康 Z7 II**；理论上支持所有 SnapBridge 智能设备模式的 Z 相机。
- 目前仅做了蓝牙模式的适配，也就是只支持 Z 卡口微单以及部分带蓝牙功能的末代单反。
- 如遇连接不上等软件 bug 或任何改进建议，请提交 [Issue](https://github.com/HowenXu/nsg/issues)，本人会不定期查看。

---

## 使用教程

### 1. 安装

从 [Releases](https://github.com/HowenXu/nsg/releases) 下载 `nsg.apk` 安装。首次打开请允许：

- 位置权限（获取 GPS）；
- 蓝牙权限（连接相机）；
- 通知权限（前台服务通知）；
- 电池优化豁免（系统弹窗里点「允许」）。

### 2. 相机已用 SnapBridge 配对过（最常见情况）

1. 打开 App，点「配对新相机」；
2. 列表中选中你的相机；
3. 如果相机已有配对记录，App 会自动破解 SnapBridge 设备标识（日志区会实时显示进度）；
4. 破解成功后自动连接，状态变为「就绪」；
5. 以后可以直接用「连接已保存相机」快速连接，与 SnapBridge 互切**无需删除配对记录**。

### 3. 全新相机（从未配对）

直接「配对新相机」→ 选中相机 → 按提示在系统弹窗完成蓝牙配对即可。

### 4. 拍照带 GPS

连接成功后（状态「就绪」），相机 LCD 会显示 GPS 图标/坐标，此时拍摄的照片 EXIF 会包含位置信息。

### 5. 后台使用

连接后可以退回桌面，App 会以前台服务方式保持连接并持续注入 GPS。建议在系统设置里把本 App 加入电池白名单/自启动白名单（国产 ROM 尤其重要）。

### 6. 高级设置

右上角 `⋮` → 「高级设置（一般无需更改）」：

- **相机端设备名**：相机显示的控制器名称（默认自动生成，一般无需改）；
- **固定设备标识**：SnapBridge 的完整 16 位设备标识。自动破解成功后会自动填入，一般无需手动改。

---

## 已知问题

- 目前仅做了蓝牙模式的适配，也就是只支持 Z 卡口微单以及部分带蓝牙功能的末代单反。
- **不要清除 SnapBridge 的数据或重装它**：否则它会重新生成设备标识，需要重新「自动提取」一次；
- 尼康相机 LCD 上的坐标显示存在固件级小数显示 bug（如 `51.002'` 显示成 `51.2'`），但写入照片 EXIF 的坐标是正确的（详见原项目说明）。
- 软件没有做图标，我很懒得搞，等一位愿意贡献的有缘人可以直接给我发 [issue](https://github.com/HowenXu/nsg/issues)😋😋

## Release 构建（CI）

Release APK 由 GitHub Actions 自动构建并发布。

**流程**

- 推送形如 `v*` 的 tag 会触发 `.github/workflows/release.yml`。
- 工作流从仓库 secrets 还原 release keystore（密钥本身不进 git），再运行 `./gradlew assembleRelease`：仅当 `NSG_SIGN_RELEASE=true` 时（由 release 工作流的 job env 设置，其他 CI 任务及无 secrets 的 fork PR 仍构建为未签名包）通过 `KEYSTORE_PATH` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` 环境变量经 `signingConfigs.release` 完成签名。
- 签名后的 `app-release.apk` 经 `apksigner verify` 与 `zipalign -c` 校验后重命名为 `nsg.apk`，附加到该 tag 的 GitHub Release。

本地 `assembleRelease` 构建恒为未签名（`app-release-unsigned.apk`），这是有意为之：无需任何 keystore 配置，任何干净 checkout 都能直接构建。未签名 APK 不能直接安装（`adb install` 会拒绝）；要在本地冒烟测试 release 构建，请自行签名：

**方案 A — 用自己的 keystore 给未签名 APK 签名**

```bash
cd android
./gradlew assembleRelease
# -> app/build/outputs/apk/release/app-release-unsigned.apk
zipalign -p -f 4 app/build/outputs/apk/release/app-release-unsigned.apk app-aligned.apk
apksigner sign --ks /path/to/your.keystore --ks-pass pass:STOREPASS --ks-key-alias ALIAS --key-pass pass:KEYPASS --out nsg-local.apk app-aligned.apk
apksigner verify --print-certs nsg-local.apk
adb install nsg-local.apk
```

（`zipalign` / `apksigner` 位于 Android SDK build-tools 中，例如 `$ANDROID_HOME/build-tools/36.0.0/`。）

**方案 B — 用临时测试 key 复现 CI 签名路径**

```bash
keytool -genkeypair -keystore /tmp/test.keystore -alias test -keyalg RSA -keysize 2048 -validity 3650 \
  -storepass test123 -keypass test123 -dname "CN=test"
cd android
NSG_SIGN_RELEASE=true KEYSTORE_PATH=/tmp/test.keystore KEYSTORE_PASSWORD=test123 KEY_ALIAS=test KEY_PASSWORD=test123 \
  ./gradlew assembleRelease
# -> app/build/outputs/apk/release/app-release.apk（已签名）
```

手动触发的工作流（`workflow_dispatch`）同样会构建、校验并签名，但产物以上传 workflow artifact 的形式提供，而不会发布 GitHub Release。

**所需的仓库 secrets**

在 **Settings -> Secrets and variables -> Actions** 中配置，缺一不可（缺失时工作流会在构建前直接失败，而不会发布坏包）：

| Secret | 含义 |
| --- | --- |
| `KEYSTORE_BASE64` | release `.keystore`/`.jks` 文件的 Base64 |
| `KEYSTORE_PASSWORD` | Keystore 密码 |
| `KEY_ALIAS` | Key 别名 |
| `KEY_PASSWORD` | Key 密码 |

**发版步骤**

1. 在 `app/build.gradle.kts` 中递增 `versionCode`/`versionName`。
2. 打 tag 并推送：`git tag v1.0.1 && git push origin v1.0.1`。
3. 从生成的 GitHub Release 下载签名好的 `nsg.apk`。
