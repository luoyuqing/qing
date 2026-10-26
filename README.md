<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# 清助理 Qing Assistant

> 你自己的 AI 助理，落在手机上。聊天窗口背后是跑在**你自己家里那台 X2** 上的 Hermes Agent（办公小爱）——
> 它能感知手机数据、连接各家 MCP 应用、每天早上和晚上自动给你写简报。

清助理是基于 [FluffyChat](https://fluffychat.im) 深度改造的私有分支（包名 `chat.qingzhuli.app`，独立签名），
聊天能力完整保留，同时把"助理"这一层做成了产品。

---

## 五个 Tab

| Tab | 做什么 |
|---|---|
| **聊天** | 和办公小爱对话。历史会话可读记录、一键切回上下文（`!resume`），新会话从右上角头像菜单进入 |
| **简报** | 每天两份：**晨报 07:30**（日程 + 待办 + 手机通知，重点提醒今天要推进的工作）与 **晚报 20:00**（当天所有会话的结论 + 还没落地的待办 + 明天先做这件）。可点「让小爱现在写」 |
| **任务** | 最近会话（点开看对话记录、可切回）与定时任务（详情、编辑、启停） |
| **记忆** | 四个选项卡：**记忆** / **画像** / **技能** / **人设**。人设就是助理的性格设定，可直接查看与编辑 |
| **设置** | 设备数据、连接应用、数据与隐私、主题与账号 |

## 特色能力

- **手机数据感知**：通知、短信验证码、日历日程、通讯录、App 使用时长、定位、文件索引。
  手机端 **清助理** 主动上报到 hub 的 device-hub，AI 按需取数（不是无脑全量同步）。
- **连接应用**：官方 MCP（高德 / 飞书 / GitHub / WPS / DeepWiki）+ 内置连接器（知乎热榜 / B站热门 / 快递100 / QQ邮箱 / 钉钉），
  凭据只存在你自己的机器上，不上手机。
- **人设可编辑**：助理的性格、语气、边界写在服务端配置里，App 里随时改，改完新会话生效。
- **简报静默**：定时生成简报**不会**往聊天窗口推送过程和结果，只有失败才提醒你。
- **统一视觉**：白卡片 + 细描边 + 渐变 Hero + 胶囊控件，参照 today.ai 的 Today 页重做。

## 架构

```
📱 清助理 App (Flutter)                 🖥️ X2（你的家用服务器）
┌──────────────────────────┐            ┌────────────────────────────────────┐
│ 聊天 / 简报 / 任务 / 记忆 │  ──Matrix──▶│ Hermes Agent（办公小爱 / 亲密小爱…） │
│ 长轮询上报 + 按需取数      │            │  · 人设 config.yaml（App 可编辑）    │
└──────────────────────────┘            │  · 记忆 MEMORY.md / 画像 USER.md     │
                                        │  · 定时任务 cron（晨报/晚报…）       │
                                        │  · 插件 device-data（取数工具）       │
                                        └──────────────┬─────────────────────┘
                                                       │ 127.0.0.1:8787
                                        ┌──────────────▼─────────────────────┐
                                        │ device-hub（纯标准库 HTTP + SQLite）│
                                        │ 设备/通知/日历/通讯录/用量/待办/简报 │
                                        │ MCP 代理 · 连接器 · 审计 · 保留策略  │
                                        └────────────────────────────────────┘
```

- **Matrix**：自建 tuwunel（`matrix.3585616.xyz`），App 与 Hermes 通过它对话。
- **device-hub**：X2 上的单文件 Python 服务（`/data/device-hub/hub.py`），只依赖标准库，数据落 SQLite（WAL）。
- **Hermes Agent**：办公小爱的人设、记忆、技能、定时任务都在它那边；App 只是它的客户端。

## 下载

安装包在 GitHub Releases（arm64）：

- **v1.6.1（当前稳定版）** → [下载](https://github.com/luoyuqing/qing-assistant/releases/download/v1.6.1/Qingzhuli-1.6.1-arm64.apk)
  （v1.7.0 的聊天页改版效果不理想，已回退；重发版见 Releases 的 `v1.6.1-r2`）
- 历史版本见 [Releases](https://github.com/luoyuqing/qing-assistant/releases)

回退点：tag `v1.6.1` / 分支 `release/v1.6.1`。

## 自己构建

**CI（推荐）**：推 `main` 或手动触发 `.github/workflows/qingzhuli-apk.yaml`，
用仓库里配置的签名证书出包，只编 arm64（`--target-platform android-arm64`），
Gradle 与 Android NDK/CMake 已做缓存，二次构建会快很多。

**本地**：

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# 签名：android/key.properties 指向 release.keystore
```

需要 Flutter 3.47.x、JDK 17、Android SDK（platforms;android-37.0、build-tools;37.0.0、platform-tools）。

## 项目结构

```
lib/
  pages/
    briefing/      简报（晨报/晚报、日期轨道、让小爱现在写）
    tasks/         任务（最近会话 + 定时任务）
    memory/        记忆（记忆/画像/技能/人设）
    connectors/    连接应用（MCP 目录 + 内置连接器）
    settings_device_hub/  设备数据（配对、状态、权限）
    chat/          FluffyChat 原生聊天内核（保留上游样式，未做改动）
  widgets/
    qing_style.dart      统一视觉组件（卡片 / Hero / 分段 / 空状态）
    qing_bottom_nav.dart 五个 Tab 底栏
  utils/device_hub/       App 侧 device-hub 客户端
```

服务端代码不在本仓库：X2 上 `/data/device-hub/`（hub.py、briefing_context.py）与
`/data/hermes/data/`（人设、记忆、插件、cron）。

## 隐私

- 手机数据只在你自己的 X2 与你自己的 Matrix 之间流转，不经第三方。
- 通知等数据默认保留 30 天，定位 14 天，可在「设置 → 数据与隐私」调整。
- 所有查询都有审计日志（谁在什么时候查了什么，不含结果内容）。

## 致谢与许可

本项目基于 [FluffyChat](https://fluffychat.im)（AGPL-3.0）改造，保留其原始版权声明与许可协议，
并向 FluffyChat 社区致谢。上游作者：Christian Kußowski 与 FluffyChat 贡献者。

仓库对外公开，仅用于个人使用与二次开发。
