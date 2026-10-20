import SwiftUI

/// Local headlines from the last 3 days.
struct NewsView: View {
    @Environment(LookoutModel.self) private var model
    @State private var web: WebLink?

    var body: some View {
        List {
            if model.news.isEmpty {
                Section {
                    Text(emptyText).font(.subheadline).foregroundStyle(Color.lkMuted).padding(.vertical, 4)
                }
                .listRowBackground(Color.lkPanel)
            } else {
                Section {
                    ForEach(model.news) { story in
                        Button { web = WebLink(url: story.url) } label: { NewsRow(story: story) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Stories that mention your town or county, found by the GDELT Project. Each one opens on the publisher's site.")
                }
                .listRowBackground(Color.lkPanel)
            }

            if let place = model.area?.place, !place.isEmpty {
                Section("More news") {
                    linkRow("Google News", place, LocalNews.googleNewsURL(place))
                    linkRow("Breaking in the last hour", place, LocalNews.googleNewsURL(place, lastHour: true))
                }
                .listRowBackground(Color.lkPanel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.lkGround)
        .navigationTitle("Local news")
        .refreshable { await model.refreshNews() }
        .task { if model.news.isEmpty { await model.refreshNews() } }
        .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    private var emptyText: String {
        if model.newsLoading { return "Looking for local stories…" }
        if model.area == nil { return "Finding your town…" }
        if model.newsFailed { return "The headline service is busy right now. Pull down to try again, or use the links below." }
        return "No local stories in the last 3 days. The links below search more widely."
    }

    private func linkRow(_ title: String, _ subtitle: String, _ url: URL?) -> some View {
        Button {
            if let url { web = WebLink(url: url) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.lkText)
                    Text(subtitle).font(.caption).foregroundStyle(Color.lkMuted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(Color.lkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NewsRow: View {
    let story: NewsStory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: story.imageURL) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() } else {
                    Color.lkPanel2.overlay(Image(systemName: "newspaper").foregroundStyle(Color.lkMuted))
                }
            }
            .frame(width: 72, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(story.title).font(.subheadline.bold()).foregroundStyle(Color.lkText).lineLimit(3)
                Text(meta).font(.caption).foregroundStyle(Color.lkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var meta: String {
        guard let d = story.date else { return story.source }
        return story.source + ", " + d.formatted(.relative(presentation: .named))
    }
}
