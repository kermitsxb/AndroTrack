# AndroRingTrack Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WidgetKit extension (Home Screen small/medium + Lock Screen accessory widgets) showing wear status and today's worn duration, with an iOS 17+ interactive toggle, reusing `Shared/` business logic directly.

**Architecture:** A new `AndroRingTrackWidget` app-extension target links `Shared/` the same way `iOS/` and `WatchAndroRingTrack Extension/` already do. It reads `HealthKitService`/`SettingsStore` directly for its `TimelineProvider` (no App Group, no IPC) and calls `RecordStore.shared.markAsWorn()/markAsRemoved()` from an `AppIntent` for the interactive toggle. `RecordStore` gains a small `#if os(iOS)` hook to reload widget timelines after a successful HealthKit write.

**Tech Stack:** Swift 5.0, WidgetKit, AppIntents (iOS 17+), the existing HealthKit-backed `Shared/` layer. Target creation is done by scripting the `xcodeproj` Ruby gem (already installed: `xcodeproj 1.27.0`) rather than the Xcode GUI.

**Spec:** `docs/superpowers/specs/2026-08-24-widget-design.md`

## Global Constraints

- iOS deployment target for the new widget extension: 15.0 (matches the app's existing floor).
- Swift version: 5.0 (matches all other targets).
- Lock Screen accessory families (`.accessoryCircular`, `.accessoryRectangular`) require iOS 16+ — guard with `@available(iOS 16.0, *)` / `if #available`.
- Interactive tap-to-toggle (`AppIntent`, `Button(intent:)`) requires iOS 17+ — guard with `@available(iOS 17.0, *)` / `if #available`; below iOS 17 the widget is non-interactive (default WidgetKit tap-opens-app behavior, no code needed for that).
- No App Group, no shared UserDefaults, no IPC — the widget extension reads HealthKit directly via `HealthKitService`, exactly like the Watch target does.
- No new persistence layer.
- Reuse existing localization convention: plain `Text("KEY")` / `NSLocalizedString("KEY", comment: "")` resolved against `Shared/en.lproj/Localizable.strings` and `Shared/fr.lproj/Localizable.strings`, which the widget target must also carry as a resource.
- Log failures via `AppLogger` with `context: "Widget"`.
- No test target exists in this project (confirmed in CLAUDE.md) — "testing" in every task below means a manual `xcodebuild` compile/build check, not `xcodebuild test`.
- `DEVELOPMENT_TEAM` for all targets is `8CKMCXN74P`; `CODE_SIGN_STYLE` is `Automatic`. Build-verification commands in this plan pass `CODE_SIGNING_ALLOWED=NO` so they can run headless without a signing identity — this is a verification convenience only, not a target setting change.

---

### Task 1: Scaffold the `AndroRingTrackWidget` Xcode target

**Files:**
- Create: `AndroRingTrackWidget/Info.plist`
- Create: `AndroRingTrackWidget/AndroRingTrackWidget.entitlements`
- Create: `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)

**Interfaces:**
- Produces: an Xcode target named `AndroRingTrackWidget` (product type `com.apple.product-type.app-extension`, bundle id `com.astralym.AndroRingTrack.widget`), embedded in the `AndroRingTrack (iOS)` app target via a new "Embed Foundation Extensions" copy-files phase, with its own auto-created scheme. A placeholder `@main` `WidgetBundle` so the target builds standalone before any real data wiring exists.

- [ ] **Step 1: Create the widget extension directory and Info.plist**

```bash
mkdir -p AndroRingTrackWidget
```

Create `AndroRingTrackWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>AndroRingTrackWidget</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
	<key>NSHealthShareUsageDescription</key>
	<string>AndroRingTrack a besoin de votre autorisation pour afficher les statistiques du port de l'anneau.</string>
	<key>NSHealthUpdateUsageDescription</key>
	<string>AndroRingTrack a besoin de votre autorisation pour mettre à jour les statistiques du port de l'anneau.</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the entitlements file**

Create `AndroRingTrackWidget/AndroRingTrackWidget.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
</dict>
</plist>
```

- [ ] **Step 3: Create a placeholder widget bundle**

Create `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

struct PlaceholderWidget: Widget {
    let kind: String = "PlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { _ in
            Text("AndroRingTrack")
        }
        .supportedFamilies([.systemSmall])
    }
}

@main
struct AndroRingTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}
```

(This placeholder is fully replaced in Task 3 once the real `WearStatusProvider`/views exist — its only job here is proving the target/build/embed wiring works.)

- [ ] **Step 4: Write the target-scaffolding script**

Create `add_widget_target.rb` at the repo root (temporary — deleted in Step 7):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')
app_target = project.targets.find { |t| t.name == 'AndroRingTrack (iOS)' }
raise 'app target not found' unless app_target

# 1. Group for the new target's files (physical dir already created in Step 1)
widget_group = project.main_group.new_group('AndroRingTrackWidget', 'AndroRingTrackWidget')

# 2. New app-extension target
widget_target = project.new_target(:app_extension, 'AndroRingTrackWidget', :ios, '15.0', nil, :swift)

widget_target.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.astralym.AndroRingTrack.widget'
  bc.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bc.build_settings['INFOPLIST_FILE'] = 'AndroRingTrackWidget/Info.plist'
  bc.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'AndroRingTrackWidget/AndroRingTrackWidget.entitlements'
  bc.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  bc.build_settings['DEVELOPMENT_TEAM'] = '8CKMCXN74P'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  bc.build_settings['SKIP_INSTALL'] = 'YES'
  bc.build_settings['MARKETING_VERSION'] = '1.0.13'
  bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# 3. Placeholder source file reference (physical file created in Step 3)
bundle_file_ref = widget_group.new_reference('AndroRingTrackWidgetBundle.swift')
widget_target.source_build_phase.add_file_reference(bundle_file_ref)

# 4. Info.plist + entitlements file references (physical files created in Steps 1-2)
widget_group.new_reference('Info.plist')
widget_group.new_reference('AndroRingTrackWidget.entitlements')

# 5. Embed the extension in the app target
app_target.add_dependency(widget_target)

embed_phase = app_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.add_file_reference(widget_target.product_reference, true)

project.save
puts 'OK'
puts project.targets.map(&:name).inspect
```

- [ ] **Step 5: Run the script**

```bash
ruby add_widget_target.rb
```

Expected output: `OK` followed by a target list that includes `"AndroRingTrackWidget"`.

- [ ] **Step 6: Verify the project file and build the new target**

```bash
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
xcodebuild -list -project AndroRingTrack.xcodeproj
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWidget -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `plutil` reports `OK`; `-list` shows `AndroRingTrackWidget` under both Targets and Schemes; the build succeeds (`** BUILD SUCCEEDED **`).

- [ ] **Step 7: Delete the one-off script and commit**

```bash
rm add_widget_target.rb
git add AndroRingTrackWidget AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat(widget): scaffold AndroRingTrackWidget extension target"
```

---

### Task 2: Link `Shared/` into the widget target and add the data layer

**Files:**
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)
- Modify: `Shared/en.lproj/Localizable.strings`
- Modify: `Shared/fr.lproj/Localizable.strings`
- Create: `AndroRingTrackWidget/WearStatusEntry.swift`
- Create: `AndroRingTrackWidget/WearStatusProvider.swift`

**Interfaces:**
- Consumes: `RingState` (`.worn`/`.off`), `HealthKitService.shared.healthKitAuthorizationStatus`, `HealthKitService.shared.fetchRecords(completion:)`, `Record` (`start`, `end`), `Day(records:)` / `Day.duration`, `SettingsStore.shared.sessionLength`, `AppLogger.error(context:_:)` — all from `Shared/`.
- Produces: `WearStatusEntry` (`TimelineEntry`: `date`, `state: RingState`, `sessionStart: Date?`, `todayDurationInHours: Double`, `goalInHours: Int`, `isAuthorized: Bool`) and `WearStatusProvider: TimelineProvider` — both consumed by Task 3/4's `Widget` structs and Task 3/4's views.

- [ ] **Step 1: Write the target-linking script**

Create `link_shared_target.rb` at the repo root (temporary — deleted in Step 3):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')
widget_target = project.targets.find { |t| t.name == 'AndroRingTrackWidget' }
raise 'widget target not found' unless widget_target

shared_group = project.main_group.children.find { |g| g.display_name == 'Shared' }
raise 'Shared group not found' unless shared_group

def each_buildable_file_recursive(group)
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
      # A variant group (e.g. localized Localizable.strings) is added as
      # a single resource, not its per-language children.
      yield child
    elsif child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
      yield child
    elsif child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      each_buildable_file_recursive(child) { |f| yield f }
    end
  end
end

added_sources = 0
added_resources = 0

each_buildable_file_recursive(shared_group) do |file_ref|
  if file_ref.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
    unless widget_target.resources_build_phase.files_references.include?(file_ref)
      widget_target.resources_build_phase.add_file_reference(file_ref)
      added_resources += 1
    end
    next
  end

  name = file_ref.path || file_ref.name
  next unless name

  if name.end_with?('.swift')
    unless widget_target.source_build_phase.files_references.include?(file_ref)
      widget_target.source_build_phase.add_file_reference(file_ref)
      added_sources += 1
    end
  end
end

project.save
puts "sources added: #{added_sources}, resources added: #{added_resources}"
```

- [ ] **Step 2: Run the script and verify**

```bash
ruby link_shared_target.rb
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `sources added: 28, resources added: 1` (all `Shared/**/*.swift` files plus the `Localizable.strings` variant group), `plutil` reports `OK`.

- [ ] **Step 3: Delete the script**

```bash
rm link_shared_target.rb
```

- [ ] **Step 4: Add new localization keys**

Add to `Shared/en.lproj/Localizable.strings` (after the `// STATS_VIEW` block):

```
// WIDGET
"WIDGET_DISPLAY_NAME" = "Wear Status";
"WIDGET_DESCRIPTION" = "Shows current wear status and today's worn duration.";
"WIDGET_UNAUTHORIZED" = "Open app to set up";
```

Add to `Shared/fr.lproj/Localizable.strings` (after the `// STATS_VIEW` block):

```
// WIDGET
"WIDGET_DISPLAY_NAME" = "Statut du port";
"WIDGET_DESCRIPTION" = "Affiche le statut de port actuel et la durée de port du jour.";
"WIDGET_UNAUTHORIZED" = "Ouvrez l'application pour configurer";
```

- [ ] **Step 5: Create the timeline entry model**

Create `AndroRingTrackWidget/WearStatusEntry.swift`:

```swift
import WidgetKit
import Foundation

struct WearStatusEntry: TimelineEntry {
    let date: Date
    let state: RingState
    let sessionStart: Date?
    let todayDurationInHours: Double
    let goalInHours: Int
    let isAuthorized: Bool
}
```

- [ ] **Step 6: Create the timeline provider**

Create `AndroRingTrackWidget/WearStatusProvider.swift`:

```swift
import WidgetKit
import Foundation

struct WearStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 1.5,
            goalInHours: SettingsStore.shared.sessionLength,
            isAuthorized: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WearStatusEntry) -> Void) {
        buildEntry { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WearStatusEntry>) -> Void) {
        buildEntry { entry in
            let reloadDelay: TimeInterval = entry.state == .worn ? 15 * 60 : 60 * 60
            let reloadDate = Date().addingTimeInterval(reloadDelay)
            completion(Timeline(entries: [entry], policy: .after(reloadDate)))
        }
    }

    private func buildEntry(completion: @escaping (WearStatusEntry) -> Void) {
        guard HealthKitService.shared.healthKitAuthorizationStatus == .sharingAuthorized else {
            completion(unauthorizedEntry())
            return
        }

        HealthKitService.shared.fetchRecords { records, error in
            if let error = error {
                AppLogger.error(context: "Widget", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                completion(self.unauthorizedEntry())
                return
            }

            let allRecords = records ?? []
            let today = Day(records: allRecords.filter {
                $0.start != nil && Calendar.current.isDateInToday($0.start!)
            })
            let lastRecord = allRecords.last
            let state: RingState = (lastRecord != nil && lastRecord!.end == nil) ? .worn : .off
            let sessionStart = state == .worn ? lastRecord?.start : nil

            let entry = WearStatusEntry(
                date: Date(),
                state: state,
                sessionStart: sessionStart,
                todayDurationInHours: today.duration,
                goalInHours: SettingsStore.shared.sessionLength,
                isAuthorized: true
            )

            DispatchQueue.main.async {
                completion(entry)
            }
        }
    }

    private func unauthorizedEntry() -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 0,
            goalInHours: SettingsStore.shared.sessionLength,
            isAuthorized: false
        )
    }
}
```

- [ ] **Step 7: Build to verify it compiles**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWidget -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. (The placeholder widget from Task 1 doesn't use `WearStatusProvider` yet — this step only proves `WearStatusEntry`/`WearStatusProvider` compile against the now-linked `Shared/` sources.)

- [ ] **Step 8: Commit**

```bash
git add AndroRingTrack.xcodeproj/project.pbxproj Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings AndroRingTrackWidget/WearStatusEntry.swift AndroRingTrackWidget/WearStatusProvider.swift
git commit -m "feat(widget): link Shared/ into widget target, add timeline data layer"
```

---

### Task 3: Home Screen widget UI (small/medium)

**Files:**
- Create: `AndroRingTrackWidget/Views/DurationFormatting.swift`
- Create: `AndroRingTrackWidget/Views/WearStatusWidgetView.swift`
- Create: `AndroRingTrackWidget/WearStatusWidget.swift`
- Modify: `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift`

**Interfaces:**
- Consumes: `WearStatusEntry`, `WearStatusProvider` (Task 2).
- Produces: `Double.formattedWidgetDuration() -> String`, `WearStatusWidgetView` (also consumed by Task 4 for shared formatting), `WearStatusWidget: Widget` (registered in the bundle; Task 4 adds a second widget alongside it).

- [ ] **Step 1: Add the duration formatting helper**

Create `AndroRingTrackWidget/Views/DurationFormatting.swift`:

```swift
import Foundation

extension Double {
    /// Formats a duration in hours as e.g. "2h05" or "45min", for compact widget display.
    func formattedWidgetDuration() -> String {
        let totalMinutes = Int((self * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes)min"
    }
}
```

- [ ] **Step 2: Create the small/medium view**

Create `AndroRingTrackWidget/Views/WearStatusWidgetView.swift`:

```swift
import SwiftUI
import WidgetKit

struct WearStatusWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WearStatusEntry

    var body: some View {
        if !entry.isAuthorized {
            unauthorizedView
        } else if family == .systemMedium {
            mediumView
        } else {
            smallView
        }
    }

    private var unauthorizedView: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
            Text("WIDGET_UNAUTHORIZED")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusIcon
            Text(entry.state == .worn ? "REMOVE" : "WEAR")
                .font(.headline)
            durationText
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                statusIcon
                Text(entry.state == .worn ? "REMOVE" : "WEAR")
                    .font(.headline)
                durationText
            }
            Spacer()
            ProgressView(value: min(entry.todayDurationInHours / Double(max(entry.goalInHours, 1)), 1.0))
                .progressViewStyle(.circular)
        }
        .padding()
    }

    private var statusIcon: some View {
        Image(systemName: entry.state == .worn ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundColor(entry.state == .worn ? .accentColor : .secondary)
    }

    @ViewBuilder
    private var durationText: some View {
        if entry.state == .worn, let start = entry.sessionStart {
            Text(start, style: .timer)
                .font(.caption)
                .monospacedDigit()
        } else {
            Text(entry.todayDurationInHours.formattedWidgetDuration())
                .font(.caption)
        }
    }
}
```

- [ ] **Step 3: Create the widget configuration**

Create `AndroRingTrackWidget/WearStatusWidget.swift`:

```swift
import WidgetKit
import SwiftUI

struct WearStatusWidget: Widget {
    let kind: String = "WearStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WearStatusWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

- [ ] **Step 4: Replace the placeholder bundle with the real widget**

Edit `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift` — replace its entire contents:

```swift
import WidgetKit
import SwiftUI

@main
struct AndroRingTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WearStatusWidget()
    }
}
```

(This removes `PlaceholderEntry`/`PlaceholderProvider`/`PlaceholderWidget` from Task 1 — they were scaffolding only.)

- [ ] **Step 5: Build to verify**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWidget -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual check in Xcode's widget preview**

Open `AndroRingTrack.xcodeproj` in Xcode, open `WearStatusWidgetView.swift`, and use the canvas preview (or `#Preview` if added) to confirm the small and medium layouts render without clipping for both worn and off states. This is a visual spot-check, not an automated step — note in the task's final review whether it was done.

- [ ] **Step 7: Commit**

```bash
git add AndroRingTrackWidget
git commit -m "feat(widget): add Home Screen small/medium widget UI"
```

---

### Task 4: Lock Screen accessory widget UI (iOS 16+)

**Files:**
- Create: `AndroRingTrackWidget/Views/WearStatusAccessoryView.swift`
- Create: `AndroRingTrackWidget/WearStatusAccessoryWidget.swift`
- Modify: `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift`

**Interfaces:**
- Consumes: `WearStatusEntry`, `WearStatusProvider` (Task 2), `Double.formattedWidgetDuration()` (Task 3).
- Produces: `WearStatusAccessoryWidget: Widget`, added to the bundle from Task 3 behind an `iOS 16` availability check.

- [ ] **Step 1: Create the accessory view**

Create `AndroRingTrackWidget/Views/WearStatusAccessoryView.swift`:

```swift
import SwiftUI
import WidgetKit

@available(iOS 16.0, *)
struct WearStatusAccessoryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WearStatusEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    private var circular: some View {
        Gauge(
            value: min(entry.todayDurationInHours / Double(max(entry.goalInHours, 1)), 1.0)
        ) {
            Image(systemName: entry.state == .worn ? "checkmark.circle.fill" : "circle")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.state == .worn ? "REMOVE" : "WEAR")
                .font(.headline)
            if entry.state == .worn, let start = entry.sessionStart {
                Text(start, style: .timer)
                    .font(.caption2)
            } else {
                Text(entry.todayDurationInHours.formattedWidgetDuration())
                    .font(.caption2)
            }
        }
    }
}
```

- [ ] **Step 2: Create the accessory widget configuration**

Create `AndroRingTrackWidget/WearStatusAccessoryWidget.swift`:

```swift
import WidgetKit
import SwiftUI

@available(iOS 16.0, *)
struct WearStatusAccessoryWidget: Widget {
    let kind: String = "WearStatusAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WearStatusAccessoryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
```

- [ ] **Step 3: Register it in the bundle**

Edit `AndroRingTrackWidget/AndroRingTrackWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct AndroRingTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WearStatusWidget()
        if #available(iOS 16.0, *) {
            WearStatusAccessoryWidget()
        }
    }
}
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWidget -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add AndroRingTrackWidget
git commit -m "feat(widget): add Lock Screen accessory widget UI"
```

---

### Task 5: Interactive toggle (iOS 17+) and timeline reload on state change

**Files:**
- Create: `AndroRingTrackWidget/ToggleWearIntent.swift`
- Modify: `AndroRingTrackWidget/Views/WearStatusWidgetView.swift`
- Modify: `Shared/Stores/RecordStore.swift`

**Interfaces:**
- Consumes: `RecordStore.shared.state`, `RecordStore.shared.markAsWorn()`, `RecordStore.shared.markAsRemoved()` (all existing, `Shared/Stores/RecordStore.swift`).
- Produces: `ToggleWearIntent: AppIntent` (iOS 17+), consumed by the small/medium widget view's tap target. `RecordStore` gains no new public API — its existing `markAsWorn()`/`markAsRemoved()` now also trigger a widget reload as a side effect.

- [ ] **Step 1: Create the App Intent**

Create `AndroRingTrackWidget/ToggleWearIntent.swift`:

```swift
import AppIntents
import WidgetKit

@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wear status"

    func perform() async throws -> some IntentResult {
        if RecordStore.shared.state == .worn {
            RecordStore.shared.markAsRemoved()
        } else {
            RecordStore.shared.markAsWorn()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- [ ] **Step 2: Wire the intent into the status icon**

Edit `AndroRingTrackWidget/Views/WearStatusWidgetView.swift` — replace the `statusIcon` property:

```swift
    private var statusIcon: some View {
        Group {
            if #available(iOS 17.0, *), entry.isAuthorized {
                Button(intent: ToggleWearIntent()) {
                    statusIconImage
                }
                .buttonStyle(.plain)
            } else {
                statusIconImage
            }
        }
    }

    private var statusIconImage: some View {
        Image(systemName: entry.state == .worn ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundColor(entry.state == .worn ? .accentColor : .secondary)
    }
```

(This replaces the old `statusIcon` body, which was the `Image(...)` directly — that image moves into the new `statusIconImage` property, wrapped in a `Button(intent:)` on iOS 17+.)

- [ ] **Step 3: Trigger widget reloads from `RecordStore`**

Edit `Shared/Stores/RecordStore.swift` — add the import near the top:

```swift
import Foundation
import UserNotifications
#if os(iOS)
import WidgetKit
#endif
```

In `markAsWorn()`, change the `storeRecord` completion:

```swift
            HealthKitService.shared.storeRecord(record: records[records.endIndex - 1]) { error in
                if let error = error {
                    AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                } else {
                    #if os(iOS)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
                }
            }
```

In `markAsRemoved()`, change both branches:

```swift
            if records[records.endIndex - 1].durationInMinutes ?? 0 < 3 {
                HealthKitService.shared.removeRecord(at: records[records.endIndex - 1].start!) { error in
                    if let error = error {
                        AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                    } else {
                        #if os(iOS)
                        WidgetCenter.shared.reloadAllTimelines()
                        #endif
                    }
                }
            } else {
                HealthKitService.shared.storeRecord(record: records[records.endIndex - 1]) { error in
                    if let error = error {
                        AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                    } else {
                        #if os(iOS)
                        WidgetCenter.shared.reloadAllTimelines()
                        #endif
                    }
                }
            }
```

- [ ] **Step 4: Build both the widget target and the watchOS target to verify the `#if os(iOS)` guard is correct**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWidget -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: both `** BUILD SUCCEEDED **` — the watchOS build proves `RecordStore.swift` still compiles without `WidgetKit` (which isn't imported there).

- [ ] **Step 5: Commit**

```bash
git add AndroRingTrackWidget Shared/Stores/RecordStore.swift
git commit -m "feat(widget): add interactive iOS 17+ toggle and timeline reload triggers"
```

---

### Task 6: Full-project verification and README update

**Files:**
- Modify: `README.md:37`

**Interfaces:** None — this task only verifies prior tasks integrate and updates project documentation.

- [ ] **Step 1: Build every target**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "AndroRingTrack (iOS)" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: both `** BUILD SUCCEEDED **`. The first command builds `AndroRingTrack (iOS)` with the widget extension embedded (via the "Embed Foundation Extensions" phase from Task 1) — this is the first point at which the embed wiring itself, not just the widget target in isolation, is verified.

- [ ] **Step 2: Update the README**

In `README.md`, under `## Feature suggestions`, change:

```
- [ ] Widget
```

to:

```
- [x] Widget
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: mark Widget as implemented in README"
```

- [ ] **Step 4: Manual on-device/simulator check**

Run the `AndroRingTrack (iOS)` scheme on a simulator or device, add the widget from the Home Screen widget gallery (and, on iOS 16+/17+ hardware, the Lock Screen), and confirm: the widget shows the correct wear status and duration, updates after toggling wear status in the app, and (iOS 17+) the tap-to-toggle button works from the widget itself. This is manual verification with no CLI equivalent — note the outcome when closing out this task.
