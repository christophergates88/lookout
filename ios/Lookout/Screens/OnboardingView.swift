import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(LocationManager.self) private var location
    @State private var page = 0

    private let pages: [(symbol: String, title: String, text: String)] = [
        ("dot.radiowaves.left.and.right", "Know what's around you",
         "Police and fire scanners, live cameras, traffic reports, warnings and local news for exactly where you are, updated as you move."),
        ("exclamationmark.triangle.fill", "Warnings the moment they matter",
         "National Weather Service alerts for your spot, with the warning area drawn on the map."),
        ("steeringwheel", "Built for the drive",
         "Drive mode gives you a big, glanceable screen, reads new alerts aloud, and finds the camera ahead.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 20) {
                        Spacer()
                        if i == 0 { LogoMark(size: 96) } else {
                            Image(systemName: pages[i].symbol).font(.system(size: 64)).foregroundStyle(Color.lkAmber)
                        }
                        Text(pages[i].title)
                            .font(.title.bold()).foregroundStyle(Color.lkText)
                            .multilineTextAlignment(.center)
                        Text(pages[i].text)
                            .font(.body).foregroundStyle(Color.lkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    location.start()
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Turn on location and start")
                    .bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.lkAmberInk)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.lkGround)
    }
}
