import SwiftUI

struct CalendarWidget: View {
    let date: Date

    var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var monthString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        return f.string(from: date).capitalized
    }

    var weekdayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE"
        return f.string(from: date).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Дата")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayString)
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monthString)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white)
                    Text(weekdayString)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(width: PanelLayout.calendarWidgetWidth, alignment: .leading)
    }
}
