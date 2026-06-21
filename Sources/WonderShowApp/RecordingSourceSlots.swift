import AppKit
import Foundation
import WonderShow

enum RecordingFeatureTier: String, CaseIterable, Codable, Hashable, Sendable {
    case free
    case vip
    case svip

    static let userDefaultsKey = "wonderShow.recordingFeatureTier.v1"

    var sourceSlotRange: ClosedRange<Int> {
        switch self {
        case .free:
            return 1...2
        case .vip:
            return 1...6
        case .svip:
            return 0...9
        }
    }

    func permitsSourceSlot(_ slot: Int) -> Bool {
        sourceSlotRange.contains(slot)
    }

    var permitsPresenterColorEffects: Bool {
        self != .free
    }

    var permitsSubjectAwareBeauty: Bool {
        self == .svip
    }

    static func load(from defaults: UserDefaults = .standard) -> RecordingFeatureTier {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let tier = RecordingFeatureTier(rawValue: rawValue) else {
            return WonderShowDistribution.defaultRecordingFeatureTier
        }
        if WonderShowDistribution.isCommunityEdition, tier == .free {
            return WonderShowDistribution.defaultRecordingFeatureTier
        }
        return tier
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .free:
            return copy.text("sourceTierFree")
        case .vip:
            return copy.text("sourceTierVIP")
        case .svip:
            return copy.text("sourceTierSVIP")
        }
    }
}

enum RecordingSourceSlotKind: String, Codable, Hashable, Sendable {
    case display
    case window
}

struct RecordingSourceSlotAssignment: Codable, Hashable, Identifiable, Sendable {
    let slot: Int
    let sourceID: ScreenCaptureSourceID
    let kind: RecordingSourceSlotKind
    let displayName: String
    let detail: String
    let width: Int
    let height: Int
    let isUserDefined: Bool

    var id: Int { slot }

    init(slot: Int, option: ScreenCaptureWindowOption, isUserDefined: Bool = true) {
        self.slot = slot
        self.sourceID = option.id
        switch option.id {
        case .display:
            self.kind = .display
        case .window:
            self.kind = .window
        }
        self.displayName = option.displayTitle
        self.detail = option.detail
        self.width = option.width
        self.height = option.height
        self.isUserDefined = isUserDefined
    }

    private enum CodingKeys: String, CodingKey {
        case slot
        case sourceID
        case kind
        case displayName
        case detail
        case width
        case height
        case isUserDefined
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slot = try container.decode(Int.self, forKey: .slot)
        sourceID = try container.decode(ScreenCaptureSourceID.self, forKey: .sourceID)
        kind = try container.decode(RecordingSourceSlotKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        detail = try container.decode(String.self, forKey: .detail)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        isUserDefined = try container.decodeIfPresent(Bool.self, forKey: .isUserDefined) ?? false
    }

    var sourcePreference: ScreenCaptureSourcePreference {
        switch sourceID {
        case .display(let displayID):
            return .selectedDisplay(displayID)
        case .window(let windowID):
            return .selectedWindows([windowID])
        }
    }
}

struct RecordingSourceSlots: Codable, Hashable, Sendable {
    static let validSlots = 0...9
    static let userDefaultsKey = "wonderShow.recordingSourceSlots.v1"

    private(set) var assignments: [RecordingSourceSlotAssignment]

    init(assignments: [RecordingSourceSlotAssignment] = []) {
        self.assignments = Self.normalized(assignments)
    }

    @discardableResult
    mutating func assign(_ option: ScreenCaptureWindowOption, to slot: Int) -> Bool {
        guard Self.validSlots.contains(slot) else {
            return false
        }
        assignments.removeAll { assignment in
            assignment.slot == slot || assignment.sourceID == option.id
        }
        assignments.append(RecordingSourceSlotAssignment(slot: slot, option: option))
        assignments = Self.normalized(assignments)
        return true
    }

    @discardableResult
    mutating func assignDefaultSlots(
        for options: [ScreenCaptureWindowOption],
        featureTier: RecordingFeatureTier
    ) -> Bool {
        let originalAssignments = assignments
        let availableIDs = Set(options.map(\.id))
        assignments = assignments.filter { assignment in
            availableIDs.contains(assignment.sourceID)
                && featureTier.permitsSourceSlot(assignment.slot)
                && assignment.isUserDefined
        }
        assignments = Self.normalized(assignments)

        var occupiedSlots = Set(assignments.map(\.slot))
        var assignedSources = Set(assignments.map(\.sourceID))
        for option in Self.defaultAssignmentOrder(options) where !assignedSources.contains(option.id) {
            guard let slot = Self.validSlots.first(where: { slot in
                featureTier.permitsSourceSlot(slot) && !occupiedSlots.contains(slot)
            }) else {
                break
            }
            assignments.append(RecordingSourceSlotAssignment(slot: slot, option: option, isUserDefined: false))
            occupiedSlots.insert(slot)
            assignedSources.insert(option.id)
        }
        assignments = Self.normalized(assignments)
        return assignments != originalAssignments
    }

    private static func defaultAssignmentOrder(
        _ options: [ScreenCaptureWindowOption]
    ) -> [ScreenCaptureWindowOption] {
        options.filter(\.id.isWindow) + options.filter(\.id.isDisplay)
    }

    mutating func clear(slot: Int) {
        assignments.removeAll { $0.slot == slot }
    }

    func assignment(for slot: Int) -> RecordingSourceSlotAssignment? {
        guard Self.validSlots.contains(slot) else {
            return nil
        }
        return assignments.first { $0.slot == slot }
    }

    func slot(for sourceID: ScreenCaptureSourceID) -> Int? {
        assignments.first { $0.sourceID == sourceID }?.slot
    }

    func resolvedPreference(
        for slot: Int,
        availableOptions: [ScreenCaptureWindowOption]
    ) -> ScreenCaptureSourcePreference? {
        guard let assignment = assignment(for: slot),
              availableOptions.contains(where: { $0.id == assignment.sourceID }) else {
            return nil
        }
        return assignment.sourcePreference
    }

    func containsAvailableAssignment(
        for slot: Int,
        availableOptions: [ScreenCaptureWindowOption]
    ) -> Bool {
        resolvedPreference(for: slot, availableOptions: availableOptions) != nil
    }

    static func load(from defaults: UserDefaults = .standard) -> RecordingSourceSlots {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let slots = try? JSONDecoder().decode(RecordingSourceSlots.self, from: data) else {
            return RecordingSourceSlots()
        }
        return slots
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    private static func normalized(
        _ assignments: [RecordingSourceSlotAssignment]
    ) -> [RecordingSourceSlotAssignment] {
        var normalized: [RecordingSourceSlotAssignment] = []
        for assignment in assignments.sorted(by: { $0.slot < $1.slot }) {
            guard validSlots.contains(assignment.slot),
                  !normalized.contains(where: { $0.slot == assignment.slot }),
                  !normalized.contains(where: { $0.sourceID == assignment.sourceID }) else {
                continue
            }
            normalized.append(assignment)
        }
        return normalized
    }
}

enum RecordingSourceSlotHotKey {
    static func slot(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Int? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.option),
              !flags.contains(.shift),
              !flags.contains(.control),
              let characters = charactersIgnoringModifiers,
              characters.count == 1,
              let slot = Int(characters),
              RecordingSourceSlots.validSlots.contains(slot) else {
            return nil
        }
        return slot
    }

    static func slot(for event: NSEvent) -> Int? {
        slot(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }
}
