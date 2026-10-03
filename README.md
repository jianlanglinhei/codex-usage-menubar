# Codex Usage Menu Bar

原生 macOS 菜单栏工具：查看 Codex 剩余额度、限时保持合盖运行，以及查看 Tibo 额外重置额度的第三方预测。

## 功能

- 电池图标显示剩余额度：大于 20% 为绿色，11%–20% 为黄色，10% 及以下为红色。
- 每 5 分钟读取已登录 Codex CLI 的 `account/rateLimits/read`，显示配额窗口、剩余百分比和重置时间。多个窗口存在时，菜单栏取最低剩余百分比。
- 额度读取失败时保留上次数据并标记异常，不把未知数据显示为零。
- “设置”子菜单包含合盖运行开关、系统热状态和过热保护。
- “Tibo 重置预测”每 5 分钟读取 [Codex Reset Monitor](https://codexreset.org/)，支持手动刷新、来源链接、缓存和过期隐藏。预测基准时间与来源检查时间分别显示。

## 环境

- macOS 13 或以上，Apple Command Line Tools / Xcode（`xcode-select --install`）。
- 已安装并完成 ChatGPT 账户登录的 Codex CLI，且支持 `codex app-server`。
- CLI 从 `~/.local/bin/codex`、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex` 查找。
- 测试使用系统工具、Swift 和 Python 3，无第三方包依赖。

## 构建与运行

```bash
./scripts/build.sh
open build/CodexUsage.app
```

要放到个人应用目录，先从旧工具菜单选择“退出”，再执行：

```bash
mkdir -p "$HOME/Applications"
ditto build/CodexUsage.app "$HOME/Applications/CodexUsage.app"
open "$HOME/Applications/CodexUsage.app"
```

构建产物使用本机 ad-hoc 签名，没有 Developer ID 公证。默认不设置开机启动。如果图标被菜单栏挤到刘海附近，可按住 Command 拖动图标调整位置。

## 合盖运行与热保护

开关默认关闭，每次开启最长 2 小时，由 macOS 弹窗请求管理员授权。底层使用 `pmset -a disablesleep 1`，临时后台守护进程在以下情况恢复 `disablesleep 0`：

- 用户手动关闭、退出程序或程序进程消失；
- 2 小时到期；
- 使用电池供电且电量降到 20% 或以下；
- 应用心跳超过 45 秒未更新。

系统 `ProcessInfo.thermalState` 达到 serious 或 critical 时，先恢复睡眠设置，再调用 `pmset sleepnow` 请求休眠；冷却后不会自动重新开启。这个接口报告热等级，不提供摄氏温度；不支持的设备可能只返回 nominal。保护只作用于本工具开启的合盖运行会话。

不安装永久特权服务、不修改 sudoers。守护逻辑测试全部使用模拟 `pmset`，不会真的禁用睡眠或触发休眠。硬件、系统版本、其他睡眠阻止程序可能影响实际行为；真实合盖/高温场景仍需在目标机器验证。运行时应保持通风；异常退出后可检查 `pmset -g`，必要时手动执行 `sudo pmset -a disablesleep 0` 恢复。

## 重置预测的边界

这不是 OpenAI 官方承诺，也不是本工具自行训练的概率模型。工具转述第三方网站的 24/48 小时试验性预测；它与个人固定额度重置时间分开。

解析的是页面公开的最终概率字段，不读取动画初始的 0%。同时校验概率范围、时间顺序和来源状态。预测基准超过 6 小时后隐藏数字；网站结构变化、网络受限或 HTTP 错误会显示失败状态，保留上次有效缓存。来源自身监测降级会在菜单中提示。

## 验证

```bash
./scripts/test.sh
./scripts/build.sh
# 可选：只读验证当前账户额度，需要网络及 Codex 登录
build/CodexUsage.app/Contents/MacOS/CodexUsage --check
```

测试覆盖到期、低电量、手动停止、进程退出、心跳过期、启用失败、过热和恢复失败，以及预测字段解析、动画占位值、越界概率、结构变化、过期来源和拦截页面。

## 本地数据

运行时在 `~/Library/Application Support/CodexUsage/` 写入预测缓存 `reset-forecast.json` 和诊断状态 `status.txt`。凭据由 Codex CLI 管理，本工具不复制或上传它们。

本仓库只包含源码、构建资源和合成测试输入，不包含本机额度数据、个人缓存、登录凭据、编译产物或第三方整站快照。应用不会向 GitHub 上传文件；第三方预测请求只读取公开页面。
