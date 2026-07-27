import SwiftUI

struct WebContainerView: View {
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color(red: 0.047, green: 0.078, blue: 0.141)
                .ignoresSafeArea()

            DayManWebView(loadError: $loadError)

            if let loadError {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "DayMan could not open",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                    Button("Dismiss") {
                        self.loadError = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding(32)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
