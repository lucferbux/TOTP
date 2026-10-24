//
//  CodeTickSchedule.swift
//  Shared (app, widget, AutoFill)
//
//  Redraw schedule for live codes. Use it instead of `.periodic(from: .now, by: 1)`.
//

import SwiftUI

/// One entry per whole second of the wall clock, so every visible code and countdown ticks in the
/// same frame and a new code appears the instant its period starts.
///
/// `.periodic(from: .now, by: 1)` starts each row at the moment it was built instead: N rows tick
/// at N different instants within the second, and their 0.3 s animations end up covering all of it.
///
/// While paused it yields a single date and stops, so a view nobody can see costs nothing — the
/// macOS menu bar panel, for one, stays alive after it closes.
struct CodeTickSchedule: TimelineSchedule {
    var isPaused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let isPaused = isPaused
        var next: Date? = startDate
        return AnyIterator {
            guard let current = next else { return nil }
            next = isPaused ? nil : Date(timeIntervalSince1970: current.timeIntervalSince1970.rounded(.down) + 1)
            return current
        }
    }
}

extension TimelineSchedule where Self == CodeTickSchedule {
    /// Once per wall-clock second; nothing at all while `paused`.
    static func codeTicks(paused: Bool = false) -> CodeTickSchedule {
        CodeTickSchedule(isPaused: paused)
    }
}

extension EnvironmentValues {
    /// Whether live codes below this point should keep ticking. The app turns it off while its
    /// window is hidden or the app lock is up.
    @Entry var liveCodesEnabled = true
}
