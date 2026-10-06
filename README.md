# Codex Usage Menu Bar

原生 macOS 菜单栏工具：查看 Codex 剩余额度、限时保持合盖运行，以及查看 Tibo 额外重置额度的第三方预测。

## 功能

- 圆环图标显示剩余额度：大于 20% 为绿色，11%–20% 为橙色，10% 及以下为红色；数据过期时图标变淡并带 `!`。
- 点按菜单栏图标打开面板，右键（或 Control 点按）弹出快捷菜单：打开面板、立即刷新、退出。
- 面板顶部大字显示最紧的额度，其余额度窗口列在下方，每项带进度条和“N 天 N 小时后重置”倒计时。
- 额度余额单独显示；同一账户相邻两次成功刷新（间隔不超过 10 分钟）余额下降时，余额行显示“正在消耗额度”，悬停显示减少量。首次读取、余额持平或增加、账户切换、余额缺失和数据过期均不显示；该提示反映最近刷新间的变化，不是实时计费状态。
- 每 5 分钟读取已登录 Codex CLI 的 `account/rateLimits/read`；打开面板时如果数据超过 2 分钟也会刷新，⌘R 手动刷新。
- 额度读取失败时保留上次数据，面板顶部显示错误和“重试”按钮，不把未知数据显示为零。
- “重置预测”卡片每 5 分钟读取 [Codex Reset Monitor](https://codexreset.org/)，显示 24/48 小时概率条、预测基准和上次重置时间，可折叠；标题旁的问号直接打开来源网站，底部带“预测依据”“重置原帖”“刷新预测”。
- “合盖继续工作”卡片是一个开关，开启后显示剩余时间，并带系统热状态标签。
- 齿轮菜单可以选择菜单栏显示方式（图标和百分比 / 仅百分比 / 仅图标）、登录时启动、打开数据目录和退出（⌘Q）。
- 界面语言跟随系统：首选语言是中文时显示简体中文，其他语言显示英文；日期和 12/24 小时制按语言和地区格式化。也可以在“系统设置 › 通用 › 语言与地区 › 应用”里单独给本工具指定语言，重新打开后生效。

## 下载

[下载 v1.0.3 · macOS Apple Silicon（ZIP）](https://github.com/jianlanglinhei/codex-usage-menubar/releases/download/v1.0.3/CodexUsage-1.0.3-macos-arm64.zip) · [全部版本与 SHA-256 校验文件](https://github.com/jianlanglinhei/codex-usage-menubar/releases)

下载后解压，将 `CodexUsage.app` 拖入“应用程序”并打开。需要先安装并登录 Codex CLI；这个安装包不包含 CLI。Intel Mac 暂无预编译安装包，可尝试在本机构建。

GitHub 按 Release 附件记录下载量，可用下列命令查看安装包计数（SHA256SUMS 单独计数，不代表应用下载）：

```bash
gh api repos/jianlanglinhei/codex-usage-menubar/releases/tags/v1.0.3 \
  --jq '.assets[] | select(.name | endswith(".zip")) | {name, download_count}'
```

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

默认本地构建使用 ad-hoc 签名。正式发布可通过 `CODE_SIGN_IDENTITY` 设置 Developer ID 证书、通过 `NOTARY_PROFILE` 指定本机钥匙串中已有的公证配置，执行 `./scripts/package.sh` 完成签名、公证、装订和 ZIP 打包。凭据不写入仓库。默认不设置开机启动，可在面板齿轮菜单里开启“登录时启动”；如果系统要求批准，到“系统设置 › 通用 › 登录项”里允许。如果图标被菜单栏挤到刘海附近，可按住 Command 拖动图标调整位置。

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
# 可选：用合成数据离屏渲染面板截图（浅色、深色、低额度+报错、加载中、菜单栏图标）
build/CodexUsage.app/Contents/MacOS/CodexUsage --snapshot /tmp/codex-usage-shots --lang en   # 或 --lang zh
```

测试覆盖到期、低电量、手动停止、进程退出、心跳过期、启用失败、过热和恢复失败，预测字段解析、动画占位值、越界概率、结构变化、过期来源和拦截页面，以及倒计时文案、颜色阈值和额度解析。`--snapshot` 不访问 Codex、网络或 `pmset`。

## 本地数据

运行时在 `~/Library/Application Support/CodexUsage/` 写入预测缓存 `reset-forecast.json` 和诊断状态 `status.txt`。凭据由 Codex CLI 管理，本工具不复制或上传它们。

本仓库只包含源码、构建资源和合成测试输入，不包含本机额度数据、个人缓存、登录凭据、编译产物或第三方整站快照。应用不会向 GitHub 上传文件；第三方预测请求只读取公开页面。
