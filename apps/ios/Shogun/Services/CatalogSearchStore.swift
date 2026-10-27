import Combine
import Foundation

@MainActor final class CatalogSearchStore: ObservableObject {
    enum Phase { case idle, loading, loadingMore, loaded, empty, failed }
    @Published var query = ""
    @Published private(set) var results: [CatalogMovie] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var error: String?
    @Published private(set) var page = 0
    @Published private(set) var totalPages = 0
    private let service: any MovieDiscoveryServicing
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0
    private var active = true
    var canLoadMore: Bool {
        page > 0 && page < totalPages && phase != .loading && phase != .loadingMore
    }
    init(service: any MovieDiscoveryServicing, debounce: Duration = .milliseconds(300)) {
        self.service = service
        self.debounce = debounce
    }
    deinit { task?.cancel() }
    func search(immediately: Bool = false) {
        guard active else { return }
        task?.cancel()
        generation += 1
        results = []
        page = 0
        totalPages = 0
        error = nil
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            phase = .idle
            return
        }
        phase = .loading
        load(query: value, page: 1, delay: immediately ? .zero : debounce)
    }
    func loadMore() {
        guard active, canLoadMore else { return }
        error = nil
        phase = .loadingMore
        load(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines), page: page + 1,
            delay: .zero)
    }
    func retry() {
        if page > 0 { loadMore() } else { search(immediately: true) }
    }
    func invalidate() {
        active = false
        generation += 1
        task?.cancel()
        results = []
        query = ""
        phase = .idle
        error = nil
        page = 0
        totalPages = 0
    }
    private func load(query: String, page: Int, delay: Duration) {
        let current = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                let response = try await service.search(query: query, page: page)
                // Services may ignore cancellation; generation also rejects obsolete query responses.
                guard !Task.isCancelled, active, current == generation else { return }
                var known = Set(results.map(\.id))
                results += response.results.filter { known.insert($0.id).inserted }
                self.page = response.page
                totalPages = response.totalPages
                phase = results.isEmpty ? .empty : .loaded
            } catch {
                guard !Task.isCancelled, active, current == generation,
                    !(error is CancellationError)
                else { return }
                self.error = (error as? DiscoveryFailure ?? .unavailable).localizedDescription
                phase = .failed
            }
        }
    }
}

@MainActor final class CatalogDetailStore: ObservableObject {
    @Published private(set) var movie: CatalogMovie
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let service: any MovieDiscoveryServicing
    init(movie: CatalogMovie, service: any MovieDiscoveryServicing) {
        self.movie = movie
        self.service = service
    }
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let value = try await service.details(id: movie.id)
            try Task.checkCancellation()
            movie = value
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = (error as? DiscoveryFailure ?? .unavailable).localizedDescription
        }
    }
}
