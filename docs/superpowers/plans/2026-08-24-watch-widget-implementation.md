# AndroRingTrack Watch Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the watch app's ClockKit complications with a WidgetKit extension covering both watch face complications (`.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`, `.accessoryInline`) and the Smart Stack widget, reusing the iOS widget's data layer.

**Architecture:** A new `AndroRingTrackWatchWidget` WidgetKit extension target, embedded in the `WatchAndroRingTrack` watch app, reuses `WearStatusProvider`/`WearStatusEntry`/`DurationFormatting.swift` by adding the existing physical files (from `AndroRingTrackWidget`) to this new target's source build phase — no duplication. A new accessory-family view covers all four watchOS complication families. `SettingsStore`'s App Group mirroring becomes cross-platform (fixing a bug found in code review) so the watch widget reads the real `sessionLength`, and `RecordStore`'s `WidgetCenter.reloadAllTimelines()` calls become cross-platform so a toggle on either device refreshes the watch's complications. `ComplicationController`/`Complications.swift`/the ClockKit complication set are deleted.

**Tech Stack:** Swift 5.0, WidgetKit (watchOS 9+), the existing HealthKit-backed `Shared/` layer. Target creation is done by scripting the `xcodeproj` Ruby gem (`xcodeproj 1.27.0`, already installed) rather than the Xcode GUI, matching how `AndroRingTrackWidget` was scaffolded.

**Spec:** `docs/superpowers/specs/2026-08-24-watch-widget-design.md`

## Global Constraints

- `WATCHOS_DEPLOYMENT_TARGET` for all watch targets (`WatchAndroRingTrack`, `WatchAndroRingTrack Extension`, and the new `AndroRingTrackWatchWidget`): 9.0. This drops Apple Watch Series 3 support — accepted per the spec.
- Swift version: 5.0 (matches all other targets).
- No tap-to-toggle interaction on the watch widget/complications — non-goal per spec.
- No new persistence, IPC, or App-Group-based data channel beyond the existing `sessionLength` mirror — HealthKit stays the source of truth; the watch widget extension reads it directly via its own HealthKit entitlement.
- App Group `group.com.astralym.AndroRingTrack` is required on: `AndroRingTrackWidget` (already has it), the new `AndroRingTrackWatchWidget`, and `WatchAndroRingTrack Extension` (currently missing it — added in Task 2).
- Reuse existing localization convention: `Shared/en.lproj/Localizable.strings` / `Shared/fr.lproj/Localizable.strings`, resolved via `Text("KEY")` / `NSLocalizedString("KEY", comment: "")`.
- Log failures via `AppLogger` with `context:` identifying the originating type, matching existing usage.
- No test target exists in this project (confirmed in CLAUDE.md) — "testing" in every task below means a manual `xcodebuild` compile/build check, not `xcodebuild test`.
- `DEVELOPMENT_TEAM` for all targets is `8CKMCXN74P`; `CODE_SIGN_STYLE` is `Automatic`; `MARKETING_VERSION` is `1.0.13`. Build-verification commands in this plan pass `CODE_SIGNING_ALLOWED=NO` so they can run headless without a signing identity — a verification convenience only, not a target setting change.
- New target bundle id: `com.astralym.AndroRingTrack.watchkitapp.widget`. `TARGETED_DEVICE_FAMILY`: `4` (watch).

---

### Task 1: Scaffold the `AndroRingTrackWatchWidget` target and bump the watchOS deployment target

**Files:**
- Create: `AndroRingTrackWatchWidget/Info.plist`
- Create: `AndroRingTrackWatchWidget/AndroRingTrackWatchWidget.entitlements`
- Create: `AndroRingTrackWatchWidget/AndroRingTrackWatchWidgetBundle.swift`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)

**Interfaces:**
- Produces: an Xcode target named `AndroRingTrackWatchWidget` (product type `com.apple.product-type.app-extension`, bundle id `com.astralym.AndroRingTrack.watchkitapp.widget`, platform watchOS), embedded in the `WatchAndroRingTrack` watch app target via its existing "Embed App Extensions" copy-files phase, with a placeholder `@main` `WidgetBundle` so the target builds standalone before any real data wiring exists. `WatchAndroRingTrack` and `WatchAndroRingTrack Extension` gain `WATCHOS_DEPLOYMENT_TARGET = 9.0`.

- [ ] **Step 1: Create the widget extension directory and Info.plist**

```bash
mkdir -p AndroRingTrackWatchWidget
```

Create `AndroRingTrackWatchWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>AndroRingTrackWatchWidget</string>
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

Create `AndroRingTrackWatchWidget/AndroRingTrackWatchWidget.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.astralym.AndroRingTrack</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Create a placeholder widget bundle**

Create `AndroRingTrackWatchWidget/AndroRingTrackWatchWidgetBundle.swift`:

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
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct AndroRingTrackWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}
```

(This placeholder is fully replaced in Task 3 once the real widget/view exist — its only job here is proving the target/build/embed wiring works.)

- [ ] **Step 4: Write the target-scaffolding script**

Create `add_watch_widget_target.rb` at the repo root (temporary — deleted in Step 7):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')
watch_app_target = project.targets.find { |t| t.name == 'WatchAndroRingTrack' }
raise 'watch app target not found' unless watch_app_target

# 1. Group for the new target's files (physical dir already created in Step 1)
widget_group = project.main_group.new_group('AndroRingTrackWatchWidget', 'AndroRingTrackWatchWidget')

# 2. New watchOS app-extension target
widget_target = project.new_target(:app_extension, 'AndroRingTrackWatchWidget', :watchos, '9.0', nil, :swift)

widget_target.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.astralym.AndroRingTrack.watchkitapp.widget'
  bc.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bc.build_settings['INFOPLIST_FILE'] = 'AndroRingTrackWatchWidget/Info.plist'
  bc.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'AndroRingTrackWatchWidget/AndroRingTrackWatchWidget.entitlements'
  bc.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  bc.build_settings['DEVELOPMENT_TEAM'] = '8CKMCXN74P'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  bc.build_settings['SKIP_INSTALL'] = 'YES'
  bc.build_settings['MARKETING_VERSION'] = '1.0.13'
  bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# 3. Placeholder source file reference (physical file created in Step 3)
bundle_file_ref = widget_group.new_reference('AndroRingTrackWatchWidgetBundle.swift')
widget_target.source_build_phase.add_file_reference(bundle_file_ref)

# 4. Info.plist + entitlements file references (physical files created in Steps 1-2)
widget_group.new_reference('Info.plist')
widget_group.new_reference('AndroRingTrackWatchWidget.entitlements')

# 5. Embed the extension in the watch app target, reusing its existing
#    "Embed App Extensions" phase (already embeds "WatchAndroRingTrack Extension").
watch_app_target.add_dependency(widget_target)

embed_phase = watch_app_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
raise 'Embed App Extensions phase not found on WatchAndroRingTrack' unless embed_phase
embed_phase.add_file_reference(widget_target.product_reference, true)

# 6. Bump watchOS deployment target to 9.0 across the existing watch targets
#    (required for WidgetKit complications; the new target above is already 9.0).
['WatchAndroRingTrack', 'WatchAndroRingTrack Extension'].each do |name|
  t = project.targets.find { |x| x.name == name }
  t.build_configurations.each { |bc| bc.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '9.0' }
end

project.save
puts 'OK'
puts project.targets.map(&:name).inspect
```

- [ ] **Step 5: Run the script**

```bash
ruby add_watch_widget_target.rb
```

Expected output: `OK` followed by a target list that includes `"AndroRingTrackWatchWidget"`.

- [ ] **Step 6: Verify the project file and build the new target**

```bash
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
xcodebuild -list -project AndroRingTrack.xcodeproj
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWatchWidget -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `plutil` reports `OK`; `-list` shows `AndroRingTrackWatchWidget` under Targets; the build succeeds (`** BUILD SUCCEEDED **`).

- [ ] **Step 7: Delete the one-off script and commit**

```bash
rm add_watch_widget_target.rb
git add AndroRingTrackWatchWidget AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat(watch-widget): scaffold AndroRingTrackWatchWidget extension target, bump watchOS min to 9.0"
```

---

### Task 2: Fix cross-platform App Group mirroring, add the watch App Group entitlement, and link `Shared/` + the widget data layer into the new target

**Files:**
- Modify: `Shared/Stores/SettingsStore.swift`
- Modify: `Shared/Stores/RecordStore.swift`
- Modify: `WatchAndroRingTrack Extension/WatchAndroRingTrack Extension.entitlements`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)

**Interfaces:**
- Consumes: `WearStatusEntry`, `WearStatusProvider` (both already exist in `AndroRingTrackWidget/`, from `docs/superpowers/plans/2026-08-24-widget-implementation.md` Task 2), `Double.formattedWidgetDuration()` (`AndroRingTrackWidget/Views/DurationFormatting.swift`).
- Produces: `SettingsStore.mirrorSessionLengthToAppGroup()` (private, called from both `init()` and `sessionLength`'s `didSet`) — no change to `SettingsStore`'s public surface. `RecordStore`'s `WidgetCenter.reloadAllTimelines()` calls are now unconditional (not `#if os(iOS)`), consumed implicitly by any process (iOS widget, watch widget) with an active `WidgetCenter` timeline. `AndroRingTrackWatchWidget` target gains all `Shared/` sources plus `WearStatusEntry.swift`/`WearStatusProvider.swift`/`DurationFormatting.swift` as target members (file references reused from `AndroRingTrackWidget`, consumed by Task 3's views/widget).

- [ ] **Step 1: Fix the `SettingsStore` App Group mirroring bug**

Edit `Shared/Stores/SettingsStore.swift` — replace the `sessionLength` property:

```swift
    @Published var sessionLength: Int {
        didSet {
            UserDefaults.standard.set(sessionLength, forKey: "sessionLength")
            #if os(iOS)
            // Mirrored into the App Group suite so the widget extension can read it.
            UserDefaults(suiteName: "group.com.astralym.AndroRingTrack")?.set(sessionLength, forKey: "sessionLength")
            #endif
            watchConnectivity.sync()
            Notifications.scheduleNotifyEnd()
        }
    }
```

with:

```swift
    @Published var sessionLength: Int {
        didSet {
            UserDefaults.standard.set(sessionLength, forKey: "sessionLength")
            mirrorSessionLengthToAppGroup()
            watchConnectivity.sync()
            Notifications.scheduleNotifyEnd()
        }
    }
```

Then edit `init()` — replace:

```swift
        sessionLength = UserDefaults.standard.nonNulInteger(forKey: "sessionLength") ?? 15
```

with:

```swift
        sessionLength = UserDefaults.standard.nonNulInteger(forKey: "sessionLength") ?? 15
        mirrorSessionLengthToAppGroup()
```

Then add the new helper method, right after `init()`'s closing brace (before the `#if os(watchOS)` block):

```swift
    /// Mirrors `sessionLength` into the App Group suite so the widget/complication
    /// extensions (which run in a separate process) can read the real goal.
    /// `didSet` never fires for the value assigned during `init()`, so `init()`
    /// calls this explicitly too — see docs/superpowers/specs/2026-08-24-watch-widget-design.md.
    private func mirrorSessionLengthToAppGroup() {
        UserDefaults(suiteName: "group.com.astralym.AndroRingTrack")?.set(sessionLength, forKey: "sessionLength")
    }
```

- [ ] **Step 2: Make `RecordStore`'s widget reload cross-platform**

Edit `Shared/Stores/RecordStore.swift` — replace the import block near the top:

```swift
import Foundation
import UserNotifications
#if os(iOS)
import WidgetKit
#endif
```

with:

```swift
import Foundation
import UserNotifications
import WidgetKit
```

Then, in `markAsWorn()`, replace:

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

with:

```swift
            HealthKitService.shared.storeRecord(record: records[records.endIndex - 1]) { error in
                if let error = error {
                    AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                } else {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
```

Then, in `markAsRemoved()`, replace both branches:

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

with:

```swift
            if records[records.endIndex - 1].durationInMinutes ?? 0 < 3 {
                HealthKitService.shared.removeRecord(at: records[records.endIndex - 1].start!) { error in
                    if let error = error {
                        AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                    } else {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            } else {
                HealthKitService.shared.storeRecord(record: records[records.endIndex - 1]) { error in
                    if let error = error {
                        AppLogger.error(context: "RecordStore", "Failure: \(error.errorDescription!)")
                    } else {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
```

- [ ] **Step 3: Add the App Group entitlement to the watch app extension**

Replace the full contents of `WatchAndroRingTrack Extension/WatchAndroRingTrack Extension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
	<key>com.apple.developer.healthkit.background-delivery</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.astralym.AndroRingTrack</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Write the target-linking script**

Create `link_watch_widget_target.rb` at the repo root (temporary — deleted in Step 6):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')
watch_widget_target = project.targets.find { |t| t.name == 'AndroRingTrackWatchWidget' }
raise 'watch widget target not found' unless watch_widget_target

def each_buildable_file_recursive(group)
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
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

shared_group = project.main_group.children.find { |g| g.display_name == 'Shared' }
raise 'Shared group not found' unless shared_group

each_buildable_file_recursive(shared_group) do |file_ref|
  if file_ref.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
    unless watch_widget_target.resources_build_phase.files_references.include?(file_ref)
      watch_widget_target.resources_build_phase.add_file_reference(file_ref)
      added_resources += 1
    end
    next
  end

  name = file_ref.path || file_ref.name
  next unless name

  if name.end_with?('.swift')
    unless watch_widget_target.source_build_phase.files_references.include?(file_ref)
      watch_widget_target.source_build_phase.add_file_reference(file_ref)
      added_sources += 1
    end
  end
end

# Reuse the iOS widget's data layer + formatting helper (not part of Shared/)
# by adding the SAME file references to this target too — no file duplication.
widget_group = project.main_group.children.find { |g| g.display_name == 'AndroRingTrackWidget' }
raise 'AndroRingTrackWidget group not found' unless widget_group

reused_names = ['WearStatusEntry.swift', 'WearStatusProvider.swift', 'DurationFormatting.swift']
reused_added = 0

each_buildable_file_recursive(widget_group) do |file_ref|
  next if file_ref.is_a?(Xcodeproj::Project::Object::PBXVariantGroup)
  name = file_ref.path || file_ref.name
  next unless name && reused_names.include?(name)

  unless watch_widget_target.source_build_phase.files_references.include?(file_ref)
    watch_widget_target.source_build_phase.add_file_reference(file_ref)
    reused_added += 1
  end
end

project.save
puts "sources added: #{added_sources}, resources added: #{added_resources}, reused widget files added: #{reused_added}"
```

- [ ] **Step 5: Run the script and verify**

```bash
ruby link_watch_widget_target.rb
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `sources added: 28, resources added: 1, reused widget files added: 3`, `plutil` reports `OK`.

- [ ] **Step 6: Delete the script**

```bash
rm link_watch_widget_target.rb
```

- [ ] **Step 7: Build to verify**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWatchWidget -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "AndroRingTrack (iOS)" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`. The watch widget target now compiles against the linked `Shared/` sources and the reused `WearStatusEntry`/`WearStatusProvider`/`DurationFormatting` files (still using the Task 1 placeholder bundle). The `WatchAndroRingTrack` build proves `RecordStore`'s now-unconditional `import WidgetKit` compiles on watchOS. The iOS build proves the same for the iOS app + widget targets.

- [ ] **Step 8: Commit**

```bash
git add AndroRingTrack.xcodeproj/project.pbxproj Shared/Stores/SettingsStore.swift Shared/Stores/RecordStore.swift "WatchAndroRingTrack Extension/WatchAndroRingTrack Extension.entitlements"
git commit -m "fix(widget): mirror sessionLength to App Group on all platforms and from init; make widget reload cross-platform"
```

---

### Task 3: Watch complication + Smart Stack widget UI

**Files:**
- Modify: `Shared/en.lproj/Localizable.strings`
- Modify: `Shared/fr.lproj/Localizable.strings`
- Create: `AndroRingTrackWatchWidget/Views/WatchWearStatusAccessoryView.swift`
- Create: `AndroRingTrackWatchWidget/WatchWearStatusWidget.swift`
- Modify: `AndroRingTrackWatchWidget/AndroRingTrackWatchWidgetBundle.swift`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)

**Interfaces:**
- Consumes: `WearStatusEntry`, `WearStatusProvider` (Task 2), `Double.formattedWidgetDuration()` (Task 2).
- Produces: `WatchWearStatusAccessoryView` (a `View`), `WatchWearStatusWidget: Widget` (registered as the bundle's only widget, replacing the Task 1 placeholder).

- [ ] **Step 1: Add the new localization key for the inline complication**

Add to `Shared/en.lproj/Localizable.strings` (in the existing `// WIDGET` block, after `"WIDGET_UNAUTHORIZED"`):

```
"WIDGET_INLINE_IN_PROGRESS" = "In progress";
```

Add to `Shared/fr.lproj/Localizable.strings` (in the existing `// WIDGET` block, after `"WIDGET_UNAUTHORIZED"`):

```
"WIDGET_INLINE_IN_PROGRESS" = "En cours";
```

- [ ] **Step 2: Create the accessory view covering all four complication families**

Create `AndroRingTrackWatchWidget/Views/WatchWearStatusAccessoryView.swift`:

```swift
import SwiftUI
import WidgetKit

struct WatchWearStatusAccessoryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WearStatusEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
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

    private var corner: some View {
        Text(entry.state == .worn ? "✓" : entry.todayDurationInHours.formattedWidgetDuration())
            .widgetLabel {
                Gauge(
                    value: min(entry.todayDurationInHours / Double(max(entry.goalInHours, 1)), 1.0)
                ) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
    }

    @ViewBuilder
    private var inline: some View {
        if entry.state == .worn {
            Text("WIDGET_INLINE_IN_PROGRESS")
        } else {
            Text("\(entry.todayDurationInHours.formattedWidgetDuration())/\(entry.goalInHours)h")
        }
    }
}
```

- [ ] **Step 3: Create the widget configuration**

Create `AndroRingTrackWatchWidget/WatchWearStatusWidget.swift`:

```swift
import WidgetKit
import SwiftUI

struct WatchWearStatusWidget: Widget {
    let kind: String = "WatchWearStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WatchWearStatusAccessoryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
```

- [ ] **Step 4: Replace the placeholder bundle with the real widget**

Edit `AndroRingTrackWatchWidget/AndroRingTrackWatchWidgetBundle.swift` — replace its entire contents:

```swift
import WidgetKit
import SwiftUI

@main
struct AndroRingTrackWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchWearStatusWidget()
    }
}
```

(This removes `PlaceholderEntry`/`PlaceholderProvider`/`PlaceholderWidget` from Task 1 — they were scaffolding only.)

- [ ] **Step 5: Write the file-registration script**

Create `add_watch_widget_views.rb` at the repo root (temporary — deleted in Step 7):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')
widget_target = project.targets.find { |t| t.name == 'AndroRingTrackWatchWidget' }
raise 'target not found' unless widget_target

widget_group = project.main_group.children.find { |g| g.display_name == 'AndroRingTrackWatchWidget' }
raise 'group not found' unless widget_group

views_group = widget_group.new_group('Views', 'Views')
view_ref = views_group.new_reference('WatchWearStatusAccessoryView.swift')
widget_target.source_build_phase.add_file_reference(view_ref)

widget_ref = widget_group.new_reference('WatchWearStatusWidget.swift')
widget_target.source_build_phase.add_file_reference(widget_ref)

project.save
puts 'OK'
```

- [ ] **Step 6: Run the script and verify**

```bash
ruby add_watch_widget_views.rb
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
rm add_watch_widget_views.rb
```

Expected: `OK`, `plutil` reports `OK`.

- [ ] **Step 7: Build to verify**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -target AndroRingTrackWatchWidget -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Manual check in Xcode's widget preview**

Open `AndroRingTrack.xcodeproj` in Xcode, open `WatchWearStatusAccessoryView.swift`, and use the canvas preview (or add a `#Preview` block) to confirm all four families (`.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`, `.accessoryInline`) render without clipping for both worn and off states. This is a visual spot-check, not an automated step — note in the task's final review whether it was done.

- [ ] **Step 9: Commit**

```bash
git add AndroRingTrackWatchWidget AndroRingTrack.xcodeproj/project.pbxproj Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(watch-widget): add complication + Smart Stack widget UI for all accessory families"
```

---

### Task 4: Remove the legacy ClockKit complications

**Files:**
- Delete: `WatchAndroRingTrack Extension/ComplicationController.swift`
- Delete: `WatchAndroRingTrack Extension/Views/Elements/Complications.swift`
- Delete: `WatchAndroRingTrack Extension/Assets.xcassets/Complication.complicationset` (directory)
- Modify: `WatchAndroRingTrack Extension/Info.plist`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (via a one-off Ruby script, deleted after use)

**Interfaces:** None — this task only removes now-superseded code; nothing added here is consumed elsewhere.

- [ ] **Step 1: Remove the `CLKComplicationPrincipalClass` key**

Edit `WatchAndroRingTrack Extension/Info.plist` — remove this key/value pair:

```xml
	<key>CLKComplicationPrincipalClass</key>
	<string>$(PRODUCT_MODULE_NAME).ComplicationController</string>
```

- [ ] **Step 2: Write the file-removal script**

Create `remove_clockkit_complications.rb` at the repo root (temporary — deleted in Step 5):

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

names_to_remove = ['ComplicationController.swift', 'Complications.swift']
removed = 0

project.files.each do |file_ref|
  name = file_ref.path || file_ref.name
  next unless name && names_to_remove.include?(File.basename(name))
  file_ref.remove_from_project
  removed += 1
end

project.save
puts "removed: #{removed}"
```

- [ ] **Step 3: Run the script and verify**

```bash
ruby remove_clockkit_complications.rb
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `removed: 2`, `plutil` reports `OK`.

- [ ] **Step 4: Delete the physical files and the script**

```bash
rm "WatchAndroRingTrack Extension/ComplicationController.swift"
rm "WatchAndroRingTrack Extension/Views/Elements/Complications.swift"
rm -rf "WatchAndroRingTrack Extension/Assets.xcassets/Complication.complicationset"
rm remove_clockkit_complications.rb
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` — proves `WatchAndroRingTrack Extension` still compiles/links with `ComplicationController`/`Complications` gone (nothing else in the codebase references `ComplicationIdentifier`, `Complications`, or `ComplicationDisplayedData`).

- [ ] **Step 6: Commit**

```bash
git add -A "WatchAndroRingTrack Extension" AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "refactor(watch-widget): remove legacy ClockKit complications, superseded by WidgetKit"
```

---

### Task 5: Full-project verification

**Files:** None — this task only verifies prior tasks integrate correctly across every target.

**Interfaces:** None.

- [ ] **Step 1: Build every scheme**

```bash
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "AndroRingTrack (iOS)" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected: both `** BUILD SUCCEEDED **`. The `WatchAndroRingTrack` build is the first point at which the "Embed App Extensions" wiring from Task 1 (embedding `AndroRingTrackWatchWidget` alongside `WatchAndroRingTrack Extension`) is verified together, not just the widget target in isolation.

- [ ] **Step 2: Manual on-device/simulator check**

Run the `WatchAndroRingTrack` scheme on a watchOS 9+ simulator or device:
- Long-press a watch face, edit it, and confirm `AndroRingTrackWatchWidget` is selectable as a complication in at least one family (e.g. a modular/infograph face's circular or corner slot) — it should show the current wear status and gauge.
- Press the Digital Crown to open the Smart Stack and confirm the same widget appears there in its rectangular layout.
- Toggle wear status from the iPhone app, then confirm the watch complication/widget updates (allow up to the 15 min/1h refresh window from `WearStatusProvider`, or force a refresh by re-opening the watch face editor).

This is manual verification with no CLI equivalent — note the outcome when closing out this task.

- [ ] **Step 3: Commit if step 2 required no follow-up changes**

If manual verification passes without needing further edits, this task requires no additional commit (Task 4's commit already reflects a fully verified state per Step 1). If verification surfaces an issue, fix it, re-run Step 1, and commit the fix with an appropriate message before considering this plan complete.
