//
//  SettingsComponents.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import AppKit

struct InfoContainer: View {
    let text: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(color)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
        }
        .padding()
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
    }
}

struct GeneralSettingToggleRowView: View {
    let setting: GeneralSettingType
    @Binding var isEnabled: Bool
    static func == (lhs: GeneralSettingToggleRowView, rhs: GeneralSettingToggleRowView) -> Bool {
        lhs.setting == rhs.setting && lhs.isEnabled == rhs.isEnabled
    }
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: setting.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(setting.iconColor)
                .frame(width: 36, height: 36)
                .background(setting.iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(setting.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}

struct WidgetRowView: View {
    let widgetType: WidgetType
    let enabledWidgetCount: Int
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    private var availableBarWidth: CGFloat {
        WidgetLayoutPolicy.availableBarWidth()
    }

    private var enabledWidgetTypes: [WidgetType] {
        settings.settings.widgetOrder.filter { widget in
            guard widget != .agent else { return false }
            switch widget {
            case .weather: return settings.settings.weatherWidgetEnabled
            case .calendar: return settings.settings.calendarWidgetEnabled
            case .shortcuts: return settings.settings.shortcutsWidgetEnabled
            case .music: return settings.settings.musicWidgetEnabled
            case .sports: return settings.settings.sportsWidgetEnabled
            case .finance: return settings.settings.financeWidgetEnabled
            case .notes: return settings.settings.notesWidgetEnabled
            case .clipboard: return settings.settings.clipboardWidgetEnabled
            case .mirror: return settings.settings.mirrorWidgetEnabled
            case .agent: return false
            }
        }
    }

    private var isAtCapacity: Bool {
        guard !isEnabledBinding.wrappedValue else { return false }
        return !WidgetLayoutPolicy.canFit(
            widgetType,
            in: enabledWidgetTypes,
            availableWidth: availableBarWidth,
            showDividers: settings.settings.showDividersBetweenWidgets
        )
    }

    private var requiredFeature: AppFeature? {
        switch widgetType {
        case .sports:
            return .sportsWidget
        case .finance:
            return .financeWidget
        default:
            return nil
        }
    }

    private var isPremiumLocked: Bool {
        guard let requiredFeature else { return false }
        return !subscriptionManager.hasAccess(to: requiredFeature)
    }

    private var baseEnabledBinding: Binding<Bool> {
        switch widgetType {
        case .weather: return $settings.settings.weatherWidgetEnabled
        case .calendar: return $settings.settings.calendarWidgetEnabled
        case .shortcuts: return $settings.settings.shortcutsWidgetEnabled
        case .music: return $settings.settings.musicWidgetEnabled
        case .sports: return $settings.settings.sportsWidgetEnabled
        case .finance: return $settings.settings.financeWidgetEnabled
        case .notes: return $settings.settings.notesWidgetEnabled
        case .clipboard: return $settings.settings.clipboardWidgetEnabled
        case .mirror: return $settings.settings.mirrorWidgetEnabled
        case .agent: return .constant(false)
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { isPremiumLocked ? false : baseEnabledBinding.wrappedValue },
            set: { newValue in
                baseEnabledBinding.wrappedValue = isPremiumLocked ? false : newValue
            }
        )
    }

    var body: some View {
        if widgetType == .agent {
            EmptyView()
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(widgetType.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    if isAtCapacity {
                        Text("Not enough notch space on this display.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                Toggle("", isOn: isEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isPremiumLocked || (isEnabledBinding.wrappedValue && enabledWidgetCount <= 1) || isAtCapacity)

                if isPremiumLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 8)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        }
    }
}

struct LiveActivityRowView: View {
    let activityType: LiveActivityType
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    private var requiredFeature: AppFeature? {
        switch activityType {
        case .sports:
            return .liveSports
        case .finance:
            return .financeLiveActivity
        default:
            return nil
        }
    }

    private var isPremiumLocked: Bool {
        guard let requiredFeature else { return false }
        return !subscriptionManager.hasAccess(to: requiredFeature)
    }

    private var baseEnabledBinding: Binding<Bool> {
        switch activityType {
        case .music: return $settings.settings.musicLiveActivityEnabled
        case .weather: return $settings.settings.weatherLiveActivityEnabled
        case .calendar: return $settings.settings.calendarLiveActivityEnabled
        case .reminders: return $settings.settings.remindersLiveActivityEnabled
        case .timers: return $settings.settings.timersLiveActivityEnabled
        case .battery: return $settings.settings.batteryLiveActivityEnabled
        case .eyeBreak: return $settings.settings.eyeBreakLiveActivityEnabled
        case .desktop: return $settings.settings.desktopLiveActivityEnabled
        case .focus: return $settings.settings.focusLiveActivityEnabled
        case .fileShelf: return $settings.settings.fileShelfLiveActivityEnabled
        case .fileProgress: return $settings.settings.fileProgressLiveActivityEnabled
        case .microphone: return $settings.settings.microphoneLiveActivityEnabled
        case .stats: return $settings.settings.statsLiveActivityEnabled
        case .finance: return $settings.settings.financeLiveActivityEnabled
        case .sports: return $settings.settings.sportsLiveActivityEnabled
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { isPremiumLocked ? false : baseEnabledBinding.wrappedValue },
            set: { newValue in
                baseEnabledBinding.wrappedValue = isPremiumLocked ? false : newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(activityType.displayName)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("", isOn: isEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isPremiumLocked)
                if isPremiumLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 8)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: expandedOptionsPadding, trailing: 20))

            if showsExpandedOptions {
                expandedOptions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    private var expandedOptionsPadding: CGFloat {
        showsExpandedOptions ? 10 : 18
    }

    private var showsExpandedOptions: Bool {
        !isPremiumLocked && baseEnabledBinding.wrappedValue && (activityType == .sports || activityType == .finance)
    }

    @ViewBuilder
    private var expandedOptions: some View {
        switch activityType {
        case .sports:
            Toggle(isOn: $settings.settings.sportsLiveActivityWhenLiveOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only when live")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Hide the sports activity when no favorite team has a live game.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        case .finance:
            Toggle(isOn: $settings.settings.financeLiveActivityActiveHoursOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only during market hours")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Hide the finance activity outside regular US trading hours.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        default:
            EmptyView()
        }
    }
}

struct FavoriteEntriesEditor: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let maxItems: Int
    @Binding var entries: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(entries.indices, id: \.self) { index in
                    HStack {
                        TextField(placeholder, text: Binding(
                            get: { entries[index] },
                            set: { entries[index] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            entries.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(entries.count <= 1)
                    }
                }

                if entries.count < maxItems {
                    Button {
                        entries.append("")
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NotificationToggleRowView: View {
    let source: NotificationSource
    @EnvironmentObject var settings: SettingsModel

    private var isEnabledBinding: Binding<Bool> {
        switch source {
        case .iMessage: return $settings.settings.iMessageNotificationsEnabled
        case .faceTime: return $settings.settings.faceTimeNotificationsEnabled
        case .airDrop: return $settings.settings.airDropNotificationsEnabled
        }
    }

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: source.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(source.iconColor)
                .frame(width: 36, height: 36)
                .background(source.iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(source.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: isEnabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }
}

struct SystemAppIconView: View {
    let app: SystemApp
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        Image(nsImage: AppIconLoader.icon(for: app.url, maxDimension: size * 2))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SystemAppRowView: View {
    let app: SystemApp
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            SystemAppIconView(app: app, size: 28, cornerRadius: 6)

            Text(app.name)
                .font(.system(size: 13))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

struct ReorderableVStack<Item: Identifiable & Equatable, Content: View>: View {
    @Binding var items: [Item]
    @ViewBuilder var content: (Item) -> Content

    @State private var draggingIndex: Int?
    @State private var dragOffset: CGSize = .zero

    init(items: Binding<[Item]>, @ViewBuilder content: @escaping (Item) -> Content) {
        self._items = items
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                content(item)
                    .offset(y: draggingIndex == index ? dragOffset.height : 0)
                    .opacity(draggingIndex == index ? 0.75 : 1)
                    .zIndex(draggingIndex == index ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .global)
                            .onChanged { value in
                                if draggingIndex == nil {
                                    draggingIndex = index
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                if let draggingIndex = draggingIndex {
                                    moveItem(from: draggingIndex, with: value)
                                }
                                withAnimation {
                                    self.draggingIndex = nil
                                    dragOffset = .zero
                                }
                            }
                    )

                if index != items.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
    }

    private func moveItem(from fromIndex: Int, with value: DragGesture.Value) {
        guard fromIndex < items.count else { return }

        let rowHeight: CGFloat = 61.0
        let verticalTranslation = value.translation.height
        let moveOffset = Int((verticalTranslation / rowHeight).rounded())

        var toIndex = fromIndex + moveOffset
        toIndex = max(0, min(items.count - 1, toIndex))

        if fromIndex != toIndex {
            let itemToMove = items.remove(at: fromIndex)
            items.insert(itemToMove, at: toIndex)
        }
    }
}

struct CustomBatterySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let thumbSize: CGFloat = 40

            let trackUsableWidth = totalWidth - (2 * horizontalPadding)
            let thumbUsableWidth = trackUsableWidth - thumbSize

            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)

            let clampedProgress = max(0.0, min(1.0, progress))

            let thumbX = (clampedProgress * thumbUsableWidth) + horizontalPadding + (thumbSize / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .padding(.horizontal, horizontalPadding)

                Circle()
                    .fill(Color(white: 0.8))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Text("\(Int(value.rounded()))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    )
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        let newX = min(max(gestureValue.location.x, horizontalPadding), totalWidth - horizontalPadding)
                        let newProgress = (newX - horizontalPadding) / thumbUsableWidth
                        var newValue = (range.upperBound - range.lowerBound) * Double(newProgress) + range.lowerBound

                        newValue = max(range.lowerBound, min(range.upperBound, newValue))

                        self.value = newValue
                    }
            )
        }
    }
}

struct CustomSliderRowView: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String
    var onEditingChanged: ((Bool) -> Void)? = nil
    var commitsContinuously: Bool = false

    @State private var draft: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: specifier, isEditing || !commitsContinuously ? draft : value))
            }
            Slider(
                value: Binding(
                    get: { draft },
                    set: { newValue in
                        draft = newValue
                        if commitsContinuously || !isEditing {
                            value = newValue
                        }
                    }
                ),
                in: range,
                onEditingChanged: { editing in
                    isEditing = editing
                    if editing {
                        draft = value
                    } else if abs(draft - value) > .ulpOfOne {
                        value = draft
                    }
                    onEditingChanged?(editing)
                }
            )
        }
        .padding()
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                draft = newValue
            }
        }
    }
}

struct SettingsContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

struct SettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background.opacity(0.15))
            )
    }
}

struct SettingsDetailRow<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack { content }.foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding()
    }
}

extension Int {
    func formattedMinutes() -> String {
        let interval = TimeInterval(self * 60)
        return interval.formatted()
    }
}

struct IdentifiableInt: Identifiable {
    let id: Int
}