//
//  CalendarDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-
//

import SwiftUI
import EventKit

private struct Weekday: Identifiable {
    let id = UUID()
    let symbol: String
}

struct CalendarDetailView: View {
    @StateObject private var viewModel = InteractiveCalendarViewModel()
    @StateObject private var calendarService = CalendarService()

    @State private var isMonthlyView: Bool = false
    @Namespace private var calendarAnimation

    private let weekdayHeaders: [Weekday] = [
        Weekday(symbol: "S"), Weekday(symbol: "M"), Weekday(symbol: "T"),
        Weekday(symbol: "W"), Weekday(symbol: "T"), Weekday(symbol: "F"),
        Weekday(symbol: "S")
    ]

    private var combinedScheduleItems: [ScheduleItem] {
        let events = calendarService.eventsForSelectedDate.compactMap { event -> ScheduleItem? in
            let id = event.eventIdentifier ?? UUID().uuidString
            guard let title = event.title, !title.isEmpty, let date = event.startDate else { return nil }
            let color = event.calendar.color != nil ? Color(nsColor: event.calendar.color) : .accentColor
            let hasTime = !event.isAllDay
            return ScheduleItem(id: id, type: .event, title: title, date: date, color: color, hasTime: hasTime)
        }

        let reminders = calendarService.remindersForSelectedDate.compactMap { reminder -> ScheduleItem? in
            let id = reminder.calendarItemIdentifier
            guard let title = reminder.title, !title.isEmpty, let components = reminder.dueDateComponents, let date = Calendar.current.date(from: components) else { return nil }
            let color = reminder.calendar.color != nil ? Color(nsColor: reminder.calendar.color) : .accentColor
            let hasTime = components.hour != nil && components.minute != nil
            return ScheduleItem(id: id, type: .reminder, title: title, date: date, color: color, hasTime: hasTime)
        }

        return (events + reminders).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if isMonthlyView {
                monthlyGridView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
            } else {
                modernWeeklyView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
            }

            scheduleListView
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
                .frame(maxHeight: isMonthlyView ? 0 : .infinity)
                .opacity(isMonthlyView ? 0 : 1)
        }
        .frame(width: 580, height: 320)
        .foregroundColor(.white)
        .onAppear {
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .onChange(of: viewModel.selectedDate) {
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
    }

    private var headerView: some View {
        let calendar = Calendar.current

        return HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text(viewModel.selectedDate.format(as: "d"))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.selectedDate.format(as: "EEE").uppercased())
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .opacity(0.7)
                    Text(viewModel.selectedDate.format(as: "MMMM yyyy"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.9)
                }
                .padding(.leading, 8)
            }

            Spacer()

            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isMonthlyView.toggle() }
                }) {
                    Image(systemName: isMonthlyView ? "calendar" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: {
                    if let newDate = calendar.date(byAdding: .day, value: -1, to: viewModel.selectedDate) {
                        withAnimation(.spring()) { viewModel.selectDate(newDate) }
                    }
                }) {
                    Image(systemName: "chevron.left").padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: { withAnimation(.spring()) { viewModel.selectDate(Date()) } }) {
                    Text("Today").font(.system(size: 13, weight: .semibold, design: .rounded)).padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: {
                    if let newDate = calendar.date(byAdding: .day, value: 1, to: viewModel.selectedDate) {
                        withAnimation(.spring()) { viewModel.selectDate(newDate) }
                    }
                }) {
                    Image(systemName: "chevron.right").padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    private var modernWeeklyView: some View {
        HStack {
            ForEach(viewModel.datesInWeek(for: viewModel.selectedDate), id: \.self) { date in
                let isSelected = date.isSameDay(as: viewModel.selectedDate)
                VStack(spacing: 6) {
                    Text(date.format(as: "EEE").uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .opacity(isSelected ? 1 : 0.5)

                    Text(date.format(as: "d"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue)
                            .matchedGeometryEffect(id: "selected_day_background", in: calendarAnimation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { viewModel.selectDate(date) }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private var monthlyGridView: some View {
        let gridColumns = Array(repeating: GridItem(.flexible()), count: 7)

        return VStack {
            HStack {
                ForEach(weekdayHeaders) { day in
                    Text(day.symbol)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .opacity(0.6)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(viewModel.monthGrid, id: \.id) { item in
                    let isSelected = item.date.isSameDay(as: viewModel.selectedDate)
                    Text(item.date.format(as: "d"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .opacity(item.isCurrentMonth ? 1.0 : 0.3)
                        .background {
                            if isSelected {
                                Circle()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected_day_background", in: calendarAnimation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                viewModel.selectDate(item.date)
                                isMonthlyView = false
                            }
                        }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    private var scheduleListView: some View {
        VStack {
            if combinedScheduleItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.green)
                    VStack {
                        Text("All Clear").font(.title3.weight(.bold))
                        Text("You have no events or reminders scheduled.").foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(combinedScheduleItems) { item in
                            DetailedScheduleItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct DetailedScheduleItemRow: View {
    let item: ScheduleItem

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Image(systemName: item.type == .event ? "calendar" : "checklist")
                    Text(item.type == .event ? "Event" : "Reminder")
                }.font(.system(size: 11, weight: .medium)).opacity(0.6)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if item.hasTime {
                    Text(item.date, style: .time).font(.system(size: 13, weight: .semibold, design: .rounded))
                } else {
                    Text("All-Day").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.8)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.25))
        .cornerRadius(8)
    }
}