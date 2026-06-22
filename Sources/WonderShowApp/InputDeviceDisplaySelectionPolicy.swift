import Foundation

enum InputDeviceDisplaySelectionPolicy {
    static func resolve<Option: Identifiable>(
        selectedID: String,
        availableOptions: [Option],
        rememberedOption: Option?,
        fallback: Option
    ) -> Option where Option.ID == String {
        if let option = availableOptions.first(where: { $0.id == selectedID }) {
            return option
        }
        if let rememberedOption, rememberedOption.id == selectedID {
            return rememberedOption
        }
        return fallback
    }
}
