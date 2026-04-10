import SwiftUI
import Vision

struct OCRPreferencesView: View {
    @AppStorage(PreferenceKeys.ocrLanguage) private var ocrLanguage: String = "en-US"
    @AppStorage(PreferenceKeys.ocrAccuracy) private var ocrAccuracy: String = "accurate"

    @State private var availableLanguages: [String] = []

    var body: some View {
        Form {
            Picker("Default Language", selection: $ocrLanguage) {
                ForEach(availableLanguages, id: \.self) { language in
                    Text(displayName(for: language))
                        .tag(language)
                }
            }

            Picker("Default Accuracy", selection: $ocrAccuracy) {
                Text("Fast").tag("fast")
                Text("Accurate").tag("accurate")
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .onAppear {
            loadLanguages()
        }
    }

    private func loadLanguages() {
        let languages = OCRService.supportedLanguages()
        availableLanguages = languages
        if !languages.contains(ocrLanguage), let first = languages.first {
            ocrLanguage = first
        }
    }

    private func displayName(for languageCode: String) -> String {
        let locale = Locale.current
        if let name = locale.localizedString(forIdentifier: languageCode) {
            return "\(name) (\(languageCode))"
        }
        return languageCode
    }
}
