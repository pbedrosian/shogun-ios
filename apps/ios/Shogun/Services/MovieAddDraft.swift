import Combine
import Foundation

struct MovieMetadata: Codable, Equatable {
    var title = ""
    var year: Int?
    var director = ""
    var synopsis = ""
    var runtimeMinutes: Int?
    var genres: [String] = []
    var posterURL = ""
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 500
            && (year.map { (1870...9999).contains($0) } ?? true)
            && (runtimeMinutes.map { (1...10000).contains($0) } ?? true)
            && director.count <= 1000 && synopsis.count <= 20000 && genres.count <= 30
            && genres.allSatisfy { !$0.isEmpty && $0.count <= 100 }
            && posterURL.count <= 2048
            && (posterURL.isEmpty || Self.artworkURL(posterURL) != nil)
    }
    static func artworkURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil,
            url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        return url
    }
    init() {}
    init(_ movie: CatalogMovie) {
        title = movie.title
        year = movie.year
        director = movie.director ?? ""
        synopsis = movie.synopsis
        runtimeMinutes = movie.runtimeMinutes
        genres = movie.genres
        posterURL = movie.posterURL?.absoluteString ?? ""
    }
}
struct MovieAddRequest: Equatable {
    let id: String
    let libraryID: String
    let providerID: Int?
    let metadata: MovieMetadata
    let formats: [MovieFormat]
    var isValid: Bool {
        UUID(uuidString: id) != nil && !libraryID.isEmpty && metadata.isValid
            && (providerID.map { $0 > 0 && $0 <= 2_147_483_647 } ?? true)
            && (1...99).contains(formats.count)
    }
}

/// Owns the open form's draft and retry identity, independent of collection refreshes.
@MainActor final class MovieAddDraft: ObservableObject {
    @Published var metadata = MovieMetadata()
    @Published var libraryID = ""
    @Published var quantities: [MovieFormat: Int] = [:]
    @Published private(set) var providerID: Int?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var manual = false
    private let discovery: any MovieDiscoveryServicing
    private var lastRequest: MovieAddRequest?
    init(discovery: any MovieDiscoveryServicing) { self.discovery = discovery }
    var formats: [MovieFormat] {
        MovieFormat.allCases.flatMap { format in
            Array(repeating: format, count: min(99, max(0, quantities[format] ?? 0)))
        }
    }
    var canSave: Bool {
        (manual || providerID != nil) && !loading && error == nil && request.isValid
    }
    private var request: MovieAddRequest {
        MovieAddRequest(
            id: lastRequest?.id ?? UUID().uuidString, libraryID: libraryID,
            providerID: providerID, metadata: metadata, formats: formats)
    }
    func saveIntent() -> MovieAddRequest {
        let next = request
        if let old = lastRequest, old.libraryID == next.libraryID,
            old.providerID == next.providerID,
            old.providerID != nil || old.metadata == next.metadata, old.formats == next.formats
        {
            return old
        }
        let value = MovieAddRequest(
            id: UUID().uuidString, libraryID: libraryID,
            providerID: providerID, metadata: metadata, formats: formats)
        lastRequest = value
        return value
    }
    func resetSelection() {
        providerID = nil
        manual = false
        loading = false
        error = nil
        metadata = MovieMetadata()
    }
    func enterManually(title: String) {
        providerID = nil
        manual = true
        loading = false
        error = nil
        metadata = MovieMetadata()
        metadata.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func select(_ movie: CatalogMovie) async {
        providerID = movie.id
        manual = false
        loading = true
        error = nil
        metadata = MovieMetadata(movie)
        do {
            let details = try await discovery.details(id: movie.id)
            try Task.checkCancellation()
            guard providerID == movie.id, !manual else { return }
            metadata = MovieMetadata(details)
            loading = false
        } catch {
            guard providerID == movie.id, !manual else { return }
            loading = false
            if !Task.isCancelled, !(error is CancellationError) {
                self.error = (error as? DiscoveryFailure ?? .unavailable).localizedDescription
            }
        }
    }
}
