// TodayControl.swift
// A Control Center (and Lock Screen) control that opens Pace Off on Today.

import AppIntents
import SwiftUI
import WidgetKit

struct TodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.paceoff.app.control.today") {
            ControlWidgetButton(action: OpenTodayIntent()) {
                Label("Today's Run", systemImage: "figure.run")
            }
        }
        .displayName("Today's Run")
        .description("Opens Pace Off on Today.")
    }
}
