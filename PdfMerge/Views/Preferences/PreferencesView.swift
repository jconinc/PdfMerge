import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            OCRPreferencesView()
                .tabItem {
                    Label("OCR", systemImage: "text.viewfinder")
                }
        }
        .frame(width: 450, height: 300)
    }
}
