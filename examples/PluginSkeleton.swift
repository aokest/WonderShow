import Foundation
import WonderShowCore

struct ExampleEffectPlugin: WonderShowEffectCatalogPlugin {
    let manifest = WonderShowPluginManifest(
        identifier: "studio.wondershow.example-effect",
        displayName: "Example Effect Plugin",
        vendor: "WonderShow",
        version: "0.1.0",
        capabilities: [.effectCatalog]
    )

    func describeEffects(context: WonderShowPluginContext) async throws -> [WonderShowEffectDescriptor] {
        [
            WonderShowEffectDescriptor(
                identifier: "studio.wondershow.example.natural-look",
                displayName: "Natural Look",
                category: .presenterBeauty,
                parameters: [
                    WonderShowEffectParameter(
                        identifier: "strength",
                        displayName: "Strength",
                        valueKind: .number,
                        defaultValue: "0.25"
                    )
                ]
            )
        ]
    }
}

