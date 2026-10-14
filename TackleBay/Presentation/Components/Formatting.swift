import SwiftUI

enum Fmt {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jjmm")
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "Today", "Tomorrow", "Yesterday", weekday within a week, otherwise a short date.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: t) { return "Tomorrow" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 99
        if days > 0 && days < 7 { return weekdayFormatter.string(from: date) }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { return fullDateFormatter.string(from: date) }
        return shortDateFormatter.string(from: date)
    }

    static func dayTime(_ date: Date, now: Date = Date()) -> String { "\(day(date, now: now)) · \(time(date))" }
    static func dayTimeComma(_ date: Date, now: Date = Date()) -> String { "\(day(date, now: now)), \(time(date))" }

    static func fullDate(_ date: Date) -> String { fullDateFormatter.string(from: date) }
    static func fullDateTime(_ date: Date) -> String { "\(fullDateFormatter.string(from: date)), \(time(date))" }

    /// "2 h 14 min", "45 min", "3 d 2 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds) / 60)
        let days = total / (24 * 60)
        let hours = (total / 60) % 24
        let minutes = total % 60
        if days > 0 { return hours > 0 ? "\(days) d \(hours) h" : "\(days) d" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    /// "08:24:10"
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    /// Short relative label for activity rows.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 90 && now >= date { return "Just now" }
        return dayTime(date, now: now)
    }

    static func parts(_ n: Int) -> String { n == 1 ? "1 Part" : "\(n) Parts" }
    static func tickets(_ n: Int) -> String { n == 1 ? "1 ticket" : "\(n) tickets" }
    static func items(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }
}

/// Painted "sea" tile used for trips (trips never get a stock harbour photo unless they are samples).
struct SeaTile: View {
    var width: CGFloat
    var height: CGFloat
    var sample = false
    var corner: CGFloat = 18

    var body: some View {
        ZStack {
            if sample {
                Image("tb_harbor_sample").resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x8ED8F5), Color(hex: 0xC9EEF9), Color(hex: 0x37C4DA), Color(hex: 0x0E86B8)],
                               startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFFB13D)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 0.28, height: width * 0.28)
                    .offset(x: width * 0.16, y: -height * 0.06)
                WaveBand()
                    .fill(Color(hex: 0x1BA9C9))
                    .frame(height: height * 0.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                WaveBand()
                    .fill(Color(hex: 0x0D7FB0))
                    .frame(height: height * 0.32)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Image(systemName: "sailboat.fill")
                    .font(.system(size: width * 0.2, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(x: -width * 0.14, y: height * 0.02)
                    .opacity(UIImage(systemName: "sailboat.fill") == nil ? 0 : 1)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct WaveBand: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15),
                   control1: CGPoint(x: rect.width * 0.3, y: rect.minY - rect.height * 0.1),
                   control2: CGPoint(x: rect.width * 0.65, y: rect.minY + rect.height * 0.45))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
