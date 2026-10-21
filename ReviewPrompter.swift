//
//  ReviewPrompter.swift
//
//  Shared App Store review prompt component used across Jon Bobrow's apps.
//  Keep this file identical in every app; tune behaviour per app with
//  `ReviewPrompter.shared.policy` at launch instead of editing it here.
//
//  How it works
//  ------------
//  1. Call `noteAppActive()` whenever the app becomes active (or attach
//     `.tracksReviewEligibility()` to the root SwiftUI view). This records
//     the first-use date and counts distinct days the app was used.
//  2. Call `recordSignificantEvent()` at moments the person got real value
//     from the app (finished a task, saved something, etc.).
//  3. Call `requestReviewIfAppropriate()` at a natural pause right after a
//     good moment — never mid-task, never on first launch, never after an
//     error. Or use `recordSignificantEvent(promptIfAppropriate: true)`.
//
//  The system decides whether the sheet actually appears (at most 3 times
//  in 365 days per app). On top of that we only ask once per app version,
//  wait `minDaysBetweenRequests` between asks, and only ask people who
//  have used the app on several days and hit enough good moments — so the
//  ask lands on people who already like the app.
//
//  Per App Store Review Guideline 5.6.1 we use only the system prompt: no
//  custom "Do you like this app?" pre-screen.
//

import Combine
import Foundation
import StoreKit
#if canImport(SwiftUI)
import SwiftUI
#endif
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class ReviewPrompter {

    struct Policy {
        /// Distinct calendar days the app must have been opened.
        var minActiveDays: Int = 3
        /// Days since the app was first opened.
        var minDaysSinceFirstUse: Int = 3
        /// Good moments (`recordSignificantEvent`) before asking.
        var minSignificantEvents: Int = 3
        /// Minimum spacing between our requests to the system.
        var minDaysBetweenRequests: Int = 120
        /// Pause before showing the sheet so it never interrupts an animation.
        var presentationDelay: TimeInterval = 1.0
    }

    static let shared = ReviewPrompter()

    /// Tune per app at launch, e.g. `ReviewPrompter.shared.policy.minSignificantEvents = 5`.
    var policy = Policy()

    private let defaults: UserDefaults
    private var requestedThisSession = false
    private var pendingRequest: Task<Void, Never>?

    private enum Key {
        static let firstUse = "ReviewPrompter.firstUseDate"
        static let lastActiveDay = "ReviewPrompter.lastActiveDay"
        static let activeDays = "ReviewPrompter.activeDays"
        static let events = "ReviewPrompter.significantEvents"
        static let lastRequestDate = "ReviewPrompter.lastRequestDate"
        static let lastRequestVersion = "ReviewPrompter.lastRequestVersion"
        static let requestCount = "ReviewPrompter.requestCount"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Signals

    /// Call when the app becomes active. Cheap and idempotent within a day.
    func noteAppActive(now: Date = Date()) {
        if defaults.object(forKey: Key.firstUse) == nil {
            defaults.set(now, forKey: Key.firstUse)
        }
        let today = Self.dayStamp(now)
        if defaults.string(forKey: Key.lastActiveDay) != today {
            defaults.set(today, forKey: Key.lastActiveDay)
            defaults.set(defaults.integer(forKey: Key.activeDays) + 1, forKey: Key.activeDays)
        }
    }

    /// Call when the person got real value from the app.
    func recordSignificantEvent(weight: Int = 1, promptIfAppropriate: Bool = false) {
        defaults.set(defaults.integer(forKey: Key.events) + max(weight, 0), forKey: Key.events)
        if promptIfAppropriate {
            requestReviewIfAppropriate()
        }
    }

    // MARK: - Asking

    /// True when every threshold in `policy` is met.
    var isEligible: Bool {
        let now = Date()
        guard !requestedThisSession else { return false }
        guard let firstUse = defaults.object(forKey: Key.firstUse) as? Date else { return false }
        guard Self.days(from: firstUse, to: now) >= policy.minDaysSinceFirstUse else { return false }
        guard defaults.integer(forKey: Key.activeDays) >= policy.minActiveDays else { return false }
        guard defaults.integer(forKey: Key.events) >= policy.minSignificantEvents else { return false }
        if defaults.string(forKey: Key.lastRequestVersion) == Self.appVersion { return false }
        if let last = defaults.object(forKey: Key.lastRequestDate) as? Date,
           Self.days(from: last, to: now) < policy.minDaysBetweenRequests {
            return false
        }
        return true
    }

    /// Asks the system to show the review sheet if `policy` allows it.
    /// Call at a natural pause, right after a good moment.
    func requestReviewIfAppropriate() {
        guard isEligible, pendingRequest == nil else { return }
        let delay = policy.presentationDelay
        pendingRequest = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingRequest = nil
            guard self.isEligible, self.presentSystemPrompt() else { return }
            self.markRequested()
        }
    }

    /// Cancels a request that is waiting out `presentationDelay`
    /// (e.g. the person started something new).
    func cancelPendingRequest() {
        pendingRequest?.cancel()
        pendingRequest = nil
    }

    #if DEBUG
    /// Clears all stored state. Debug builds only.
    func reset() {
        [Key.firstUse, Key.lastActiveDay, Key.activeDays, Key.events,
         Key.lastRequestDate, Key.lastRequestVersion, Key.requestCount]
            .forEach { defaults.removeObject(forKey: $0) }
        requestedThisSession = false
        cancelPendingRequest()
    }
    #endif

    // MARK: - Internals

    private func markRequested(now: Date = Date()) {
        requestedThisSession = true
        defaults.set(now, forKey: Key.lastRequestDate)
        defaults.set(Self.appVersion, forKey: Key.lastRequestVersion)
        defaults.set(defaults.integer(forKey: Key.requestCount) + 1, forKey: Key.requestCount)
    }

    /// Returns true if a request was handed to StoreKit.
    private func presentSystemPrompt() -> Bool {
        #if os(iOS) || os(visionOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard UIApplication.shared.applicationState == .active,
              let scene = scenes.first(where: { $0.activationState == .foregroundActive }) else {
            return false
        }
        AppStore.requestReview(in: scene)
        return true
        #elseif os(macOS)
        guard NSApp.isActive else { return false }
        if #available(macOS 13.0, *),
           let controller = NSApp.keyWindow?.contentViewController
            ?? NSApp.windows.first(where: { $0.isVisible })?.contentViewController {
            AppStore.requestReview(in: controller)
        } else {
            SKStoreReviewController.requestReview()
        }
        return true
        #else
        return false
        #endif
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

#if canImport(SwiftUI)
private struct ReviewEligibilityTracker: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        content
            .onAppear { ReviewPrompter.shared.noteAppActive() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                ReviewPrompter.shared.noteAppActive()
            }
        #elseif os(macOS)
        content
            .onAppear { ReviewPrompter.shared.noteAppActive() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                ReviewPrompter.shared.noteAppActive()
            }
        #else
        content
            .onAppear { ReviewPrompter.shared.noteAppActive() }
        #endif
    }
}

extension View {
    /// Counts days of use for `ReviewPrompter`. Attach once, to the root view.
    func tracksReviewEligibility() -> some View {
        modifier(ReviewEligibilityTracker())
    }
}
#endif
