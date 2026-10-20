import Foundation

/// A recent news story that mentions your town or county.
struct NewsStory: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let source: String
    let url: URL
    let imageURL: URL?
    let date: Date?
}

/// Local headlines from the GDELT Project's open news index (free, no key).
enum LocalNews {
    private struct Response: Decodable {
        struct Article: Decodable {
            let url: String?
            let title: String?
            let seendate: String?
            let socialimage: String?
            let domain: String?
        }
        let articles: [Article]?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Stories from the last 3 days that name the town, or the county together with its state, newest first.
    /// County names repeat across states (Putnam County exists in several), so a county only counts
    /// when the article says "Putnam County, Georgia"; the town just has to appear with the state somewhere.
    static func stories(for area: LocalArea) async throws -> [NewsStory] {
        var names: [String] = []
        if let city = area.city { names.append("\"\(city)\"") }
        if let county = area.county, county != area.city {
            names.append(area.stateName.map { "\"\(county) \($0)\"" } ?? "\"\(county)\"")
        }
        guard !names.isEmpty else { return [] }
        let place = names.count > 1 ? "(" + names.joined(separator: " OR ") + ")" : names[0]
        let state = area.stateName.map { " \"\($0)\"" } ?? ""
        var comps = URLComponents(string: "https://api.gdeltproject.org/api/v2/doc/doc")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: place + state + " sourcecountry:US sourcelang:english"),
            URLQueryItem(name: "mode", value: "artlist"),
            URLQueryItem(name: "maxrecords", value: "40"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "sort", value: "datedesc"),
            URLQueryItem(name: "timespan", value: "3d")
        ]
        guard let url = comps.url else { return [] }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // When busy, GDELT answers with a plain-text note instead of JSON; that throws here.
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        let dateParser: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f
        }()

        var seen = Set<String>()
        var out: [NewsStory] = []
        for a in decoded.articles ?? [] {
            guard let link = a.url, let u = URL(string: link), u.scheme == "https" || u.scheme == "http",
                  let rawTitle = a.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else { continue }
            let key = String(rawTitle.lowercased().prefix(60))
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let image = a.socialimage.flatMap { URL(string: $0) }.flatMap { $0.scheme == "https" ? $0 : nil }
            out.append(NewsStory(
                id: link,
                title: rawTitle,
                source: a.domain ?? u.host ?? "",
                url: u,
                imageURL: image,
                date: a.seendate.flatMap { dateParser.date(from: $0) }
            ))
        }
        return out
    }

    /// Google News search for a place, used as a fallback and a "more" link.
    static func googleNewsURL(_ query: String, lastHour: Bool = false) -> URL? {
        var comps = URLComponents(string: "https://news.google.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: lastHour ? query + " when:1h" : query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        return comps.url
    }
}
