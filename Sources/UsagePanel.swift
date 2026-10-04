import SwiftUI

extension QuotaLevel {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .low: return .orange
        case .critical: return .red
        }
    }
}

struct UsagePanel: View {
    @ObservedObject var model: UsageModel
    var quit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                header(now: context.date)
                if let error = model.error { ErrorBanner(text: error, retry: model.refresh, busy: model.fetching) }
                quotaSection(now: context.date)
                ForecastCard(snapshot: model.forecast.snapshot, fetching: model.forecast.fetching, error: model.forecast.error,
                             hasPost: model.forecast.postURL != nil, now: context.date,
                             openLive: model.forecast.openLive, openPost: model.forecast.openPost, refresh: model.forecast.refresh)
                SleepCard(state: model.sleep, thermal: model.thermalState, now: context.date, toggle: model.toggleSleep)
                footer
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Codex 额度", "Codex Usage")).font(.headline)
                Text(updateText(now: now))
                    .font(.caption)
                    .foregroundColor(model.stale && !model.fetching ? .orange : .secondary)
            }
            Spacer()
            Button(action: model.refresh) {
                if model.fetching {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise").frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .disabled(model.fetching)
            .help(tr("立即刷新（⌘R）", "Refresh now (⌘R)"))
        }
    }

    private func updateText(now: Date) -> String {
        if model.fetching { return tr("正在刷新…", "Refreshing…") }
        guard let lastUpdate = model.lastUpdate else { return model.error == nil ? tr("正在读取…", "Loading…") : tr("尚未读取到额度", "No usage data yet") }
        let age = ageText(lastUpdate, now: now)
        return now.timeIntervalSince(lastUpdate) > 600 ? age + tr(" · 数据可能已过期", " · may be out of date") : age
    }

    @ViewBuilder
    private func quotaSection(now: Date) -> some View {
        if let tightest = model.tightest {
            let others = model.windows.filter { $0.windowDurationMins != tightest.windowDurationMins }
            VStack(alignment: .leading, spacing: 12) {
                Hero(window: tightest, now: now, windowCount: model.windows.count)
                if !others.isEmpty || model.limits?.reserve != nil {
                    Divider()
                    ForEach(Array(others.enumerated()), id: \.offset) { _, window in
                        WindowRow(window: window, now: now)
                    }
                    if let reserve = model.limits?.reserve {
                        WindowRow(window: reserve, now: now, title: tr("备用模型", "Fallback model"))
                    }
                }
            }
            .card()
        } else {
            HStack(spacing: 8) {
                if model.fetching || model.error == nil { ProgressView().controlSize(.small) }
                Text(model.fetching || model.error == nil ? tr("正在从 Codex 读取额度…", "Reading limits from Codex…") : tr("暂无额度数据", "No usage data"))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .card()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note = model.launchAtLoginNote {
                Text(note).font(.caption2).foregroundColor(.orange)
            }
            footerBar
        }
    }

    private var footerBar: some View {
        HStack {
            Text(tr("每 5 分钟自动刷新", "Refreshes every 5 minutes")).font(.caption).foregroundColor(.secondary)
            Spacer()
            Menu {
                Picker(tr("菜单栏显示", "Menu bar shows"), selection: $model.barStyle) {
                    ForEach(BarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle(tr("登录时启动", "Open at login"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                Divider()
                Button(tr("打开数据目录", "Open data folder"), action: model.openDataDirectory)
                Divider()
                Button(tr("退出 Codex 额度", "Quit Codex Usage"), action: quit).keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("设置", "Settings"))
        }
    }
}

private struct Hero: View {
    let window: Window
    let now: Date
    let windowCount: Int

    var body: some View {
        let level = QuotaLevel(remaining: window.remaining)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(window.remaining)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(level.color)
                Text("%").font(.title3.weight(.semibold)).foregroundColor(level.color)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(windowCount > 1 ? tr("最紧的额度", "Tightest limit") : tr("剩余额度", "Remaining")).font(.caption).foregroundColor(.secondary)
                    Text(window.label).font(.subheadline.weight(.medium))
                }
            }
            QuotaBar(fraction: Double(window.remaining) / 100, color: level.color, height: 8)
            if let reset = window.resetDate {
                Label(resetText(reset, now: now) + " · " + shortDateTime(reset), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct WindowRow: View {
    let window: Window
    let now: Date
    var title: String?

    var body: some View {
        let level = QuotaLevel(remaining: window.remaining)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title ?? window.label).font(.subheadline)
                Spacer()
                Text("\(window.remaining)%").font(.subheadline.weight(.medium)).monospacedDigit().foregroundColor(level.color)
            }
            QuotaBar(fraction: Double(window.remaining) / 100, color: level.color, height: 4)
            if let reset = window.resetDate {
                Text(resetText(reset, now: now) + " · " + shortDateTime(reset))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .help(window.resetDate.map { tr("重置时间：", "Resets at ") + shortDateTime($0) } ?? "")
    }
}

private struct QuotaBar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width: max(fraction > 0 ? height : 0, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

private struct ErrorBanner: View {
    let text: String
    let retry: () -> Void
    let busy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(tr("重试", "Retry"), action: retry).controlSize(.small).disabled(busy)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

private struct ForecastCard: View {
    let snapshot: ResetForecast?
    let fetching: Bool
    let error: String?
    let hasPost: Bool
    let now: Date
    let openLive: () -> Void
    let openPost: () -> Void
    let refresh: () -> Void
    @AppStorage("forecastExpanded") private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundColor(.purple)
                    Text(tr("额外重置预测", "Bonus reset forecast")).font(.subheadline.weight(.medium))
                    Text(tr("非官方", "Unofficial")).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08))).foregroundColor(.secondary)
                    Spacer()
                    if !expanded, let summary { Text(summary).font(.caption).foregroundColor(.secondary) }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { details }
        }
        .card()
    }

    private var summary: String? {
        guard let snapshot, snapshot.isFresh(at: now) else { return nil }
        return "24h \(snapshot.probability24h)% · 48h \(snapshot.probability48h)%"
    }

    @ViewBuilder
    private var details: some View {
        if let snapshot {
            if snapshot.isFresh(at: now) {
                VStack(spacing: 6) {
                    ProbabilityRow(title: tr("24 小时内", "Within 24h"), value: snapshot.probability24h)
                    ProbabilityRow(title: tr("48 小时内", "Within 48h"), value: snapshot.probability48h)
                }
            } else {
                Text(tr("来源预测已超过 6 小时，暂不显示概率", "Forecast is over 6 hours old; odds hidden")).font(.caption).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("预测基准 ", "Forecast ") + shortDateTime(snapshot.baseDate) + tr(" · 上次重置 ", " · Last reset ") + shortDateTime(snapshot.latestResetAt))
                if snapshot.sourceDegraded == true {
                    Label(tr("来源部分监测异常，仅供参考", "Source monitoring degraded; treat as a rough guide"), systemImage: "exclamationmark.circle").foregroundColor(.orange)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        } else {
            Text(fetching ? tr("正在读取预测…", "Loading forecast…") : tr("暂时没有可用预测", "No forecast available")).font(.caption).foregroundColor(.secondary)
        }
        if let error {
            Text(tr("更新失败：", "Update failed: ") + error).font(.caption2).foregroundColor(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            Button(tr("预测依据", "Details"), action: openLive)
            Button(tr("重置原帖", "Reset post"), action: openPost).disabled(!hasPost)
            Spacer()
            Button(fetching ? tr("刷新中…", "Refreshing…") : tr("刷新预测", "Refresh"), action: refresh).disabled(fetching)
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}

private struct ProbabilityRow: View {
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundColor(.secondary).frame(width: 66, alignment: .leading)
            QuotaBar(fraction: Double(value) / 100, color: .purple.opacity(0.75), height: 6)
            Text("\(value)%").font(.caption.weight(.medium)).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
    }
}

private struct SleepCard: View {
    let state: SleepDisplay
    let thermal: ProcessInfo.ThermalState
    let now: Date
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: state.active ? "laptopcomputer" : "moon.zzz")
                    .foregroundColor(state.active ? .blue : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("合盖继续工作", "Keep working with lid closed")).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundColor(state.active ? .blue : .secondary)
                }
                Spacer()
                if state.busy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { state.active }, set: { _ in toggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(state.busy)
            }
            if let message = state.message {
                Text(message).font(.caption2).foregroundColor(.orange)
            }
            HStack(spacing: 6) {
                Label(SleepKeeper.thermalLevel(thermal), systemImage: "thermometer.medium")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(thermalColor.opacity(0.15)))
                    .foregroundColor(thermalColor)
                Text(tr("电量 ≤20%、过热、到时或退出后自动恢复", "Auto-off at ≤20% battery, heat, timeout or quit")).font(.caption2).foregroundColor(.secondary)
            }
        }
        .card()
        .help(tr("开启时需要管理员授权；合盖运行请放在通风处", "Needs administrator approval. Keep the Mac ventilated while the lid is closed."))
    }

    private var subtitle: String {
        if state.busy { return tr("正在更改睡眠设置…", "Changing sleep settings…") }
        if state.active, let deadline = state.deadline { let left = durationText(max(0, deadline.timeIntervalSince(now))); return tr("已开启 · 还剩 \(left)", "On · \(left) left") }
        if state.active { return tr("系统睡眠已被其他设置关闭", "Sleep disabled by another setting") }
        return tr("限时 2 小时，开启需要管理员授权", "Up to 2 hours · needs admin approval")
    }

    private var thermalColor: Color {
        switch thermal {
        case .nominal: return .green
        case .fair: return .orange
        default: return .red
        }
    }
}

private extension View {
    func card() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }
}
