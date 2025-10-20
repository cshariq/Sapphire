//
//  CalendarWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27.
//

import SwiftUI
import EventKit

struct ScheduleItem: Identifiable {
    enum ItemType { case event, reminder }

    let id: String
    let type: ItemType
    let title: String
    let date: Date
    let color: Color
    let hasTime: Bool
}

struct CenterDateInfo: Equatable {
    let date: Date
    let distance: CGFloat
}
struct CenterDatePreferenceKey: PreferenceKey {
    typealias Value = CenterDateInfo?
    static var defaultValue: Value = nil
    static func reduce(value: inout Value, nextValue: () -> Value) {
        guard let next = nextValue() else { return }
        if value == nil || next.distance < value!.distance {
            value = next
        }
    }
}

struct CalendarWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @ObservedObject var viewModel: InteractiveCalendarViewModel
    @EnvironmentObject var calendarService: CalendarService

    @State private var hasScrolledInitially = false
    @State private var selectionWorkItem: DispatchWorkItem?

    private var combinedScheduleItems: [ScheduleItem] {
        let events = calendarService.eventsForSelectedDate.compactMap { event -> ScheduleItem? in
            guard let id = event.eventIdentifier as String?, !id.isEmpty,
                  let title = event.title, !title.isEmpty,
                  let date = event.startDate else { return nil }
            let color = event.calendar.color != nil ? Color(nsColor: event.calendar.color) : .accentColor
            let hasTime = !event.isAllDay

            return ScheduleItem(id: id, type: .event, title: title, date: date, color: color, hasTime: hasTime)
        }

        let reminders = calendarService.remindersForSelectedDate.compactMap { reminder -> ScheduleItem? in
            guard let id = reminder.calendarItemIdentifier as String?, !id.isEmpty,
                  let title = reminder.title, !title.isEmpty,
                  let components = reminder.dueDateComponents,
                  let date = components.date else { return nil }
            let color = reminder.calendar.color != nil ? Color(nsColor: reminder.calendar.color) : .accentColor
            let hasTime = components.hour != nil && components.minute != nil
            return ScheduleItem(id: id, type: .reminder, title: title, date: date, color: color, hasTime: hasTime)
        }

        return (events + reminders).sorted { $0.date < $1.date }
    }

    init(viewModel: InteractiveCalendarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                Text(viewModel.selectedMonthAbbreviated)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 55, alignment: .leading)
                    .padding(.top, 2)
                    .id("Month-\(viewModel.selectedMonthAbbreviated)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -10)),
                        removal: .opacity.combined(with: .offset(y: 10))
                    ))

                interactiveCalendar()
            }

            scheduleView
        }
        .padding(.top, 10)
        .frame(width: 240, height: 100)
        .foregroundColor(.white)
        .environmentObject(viewModel)
        .onChange(of: viewModel.selectedDate) {
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                navigationStack.wrappedValue.append(.calendarPlayer)
            }
        }
    }

    private func interactiveCalendar() -> some View {
        ScrollViewReader { proxy in
            GeometryReader { containerProxy in
                let itemWidth: CGFloat = 28
                let itemSpacing: CGFloat = 10
                let horizontalPadding = (containerProxy.size.width / 2) - (itemWidth / 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: itemSpacing) {
                        ForEach(viewModel.dates, id: \.self) { date in
                            DynamicDayView(
                                date: date,
                                containerMidX: containerProxy.frame(in: .global).midX
                            )
                            .id(date)
                            .onTapGesture {
                                HapticManager.shared.perform(HapticFeedbackType.medium)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    viewModel.selectDate(date)
                                    proxy.scrollTo(date, anchor: .center)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(viewModel.today, anchor: .center)
                        hasScrolledInitially = true
                    }
                }
                .onPreferenceChange(CenterDatePreferenceKey.self) { centerInfo in
                    guard hasScrolledInitially, let newDate = centerInfo?.date else { return }

                    selectionWorkItem?.cancel()

                    let workItem = DispatchWorkItem {
                        if !newDate.isSameDay(as: viewModel.selectedDate) {
                            HapticManager.shared.perform(HapticFeedbackType.weak)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectDate(newDate)
                            }
                        }
                    }

                    selectionWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
                }
            }
            .frame(height: 36)
        }
    }

    @ViewBuilder
    private var scheduleView: some View {
        let upcomingItems = combinedScheduleItems.filter { item in
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                return item.hasTime ? item.date > Date() : true
            }
            return true
        }

        if upcomingItems.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text(Calendar.current.isDateInToday(viewModel.selectedDate) ? "No more items today" : "No items scheduled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let scrollView = ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upcomingItems) { item in
                        ScheduleItemRowView(item: item)
                    }
                }
            }

            if upcomingItems.count >= 3 {
                scrollView
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.8),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                scrollView
            }
        }
    }
}

struct ScheduleItemRowView: View {
    let item: ScheduleItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.type == .event ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundColor(item.color)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            if item.hasTime {
                Text(item.date, style: .time)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text("All-Day")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DynamicDayView: View {
    let date: Date
    let containerMidX: CGFloat

    @EnvironmentObject private var viewModel: InteractiveCalendarViewModel

    var body: some View {
        let isSelected = date.isSameDay(as: viewModel.selectedDate)
        let dayName = date.format(as: isSelected ? "EEE" : "EEEEE").uppercased()

        GeometryReader { itemProxy in
            let itemMidX = itemProxy.frame(in: .global).midX
            let distance = itemMidX - containerMidX

            let absDistance = abs(distance)
            let focusFactor = max(0, 1 - (absDistance / 80))

            let scale = 0.7 + (focusFactor * 0.7)
            let opacity = 0.5 + (focusFactor * 0.5)
            let blur = (1 - focusFactor) * 1.5
            let rotationAngle = Angle.degrees(Double(distance / 10))

            let baseColor = date.isWeekend ? Color.red.opacity(0.8) : Color.white.opacity(0.8)
            let finalColor = baseColor.lerp(to: .blue, t: focusFactor)
            let dayLetterColor = Color.gray.lerp(to: .blue, t: focusFactor)

            VStack(spacing: 3) {
                Text(dayName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(dayLetterColor)
                    .id(dayName)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 10).combined(with: .opacity),
                            removal: .offset(y: -10).combined(with: .opacity)
                        )
                    )

                Text(date.format(as: "d"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(finalColor)
            }
            .drawingGroup()
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
            .rotation3DEffect(rotationAngle, axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .frame(width: itemProxy.size.width, height: itemProxy.size.height)
            .preference(key: CenterDatePreferenceKey.self, value: CenterDateInfo(date: date, distance: absDistance))
        }
        .frame(width: 28)
    }
}