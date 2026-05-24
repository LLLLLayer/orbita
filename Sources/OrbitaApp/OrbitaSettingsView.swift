import SwiftUI

enum OrbitaLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }
}

enum ScanRefreshPolicy: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes:
            return "30 minutes"
        case .oneHour:
            return "1 hour"
        case .automatic:
            return "Automatic"
        case .manual:
            return "Manual"
        }
    }

    func cacheTTLMinutes(isEnvironment: Bool) -> Int? {
        switch self {
        case .thirtyMinutes:
            return 30
        case .oneHour:
            return 60
        case .automatic:
            return isEnvironment ? 60 : 30
        case .manual:
            return nil
        }
    }
}

struct OrbitaSettingsView: View {
    @Binding var refreshPolicy: String
    @Binding var languageCode: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Scan")
                    .font(.headline)

                Picker("Refresh", selection: $refreshPolicy) {
                    ForEach(ScanRefreshPolicy.allCases) { policy in
                        Text(policy.title).tag(policy.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)

                Picker("Display language", selection: $languageCode) {
                    ForEach(OrbitaLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .presentationBackground(.regularMaterial)
    }
}
