import Foundation
import Observation

@MainActor protocol InstrumentSearching {
    func searchInstruments(_ query: String) async throws -> [APICatalogItem]
}

@MainActor @Observable final class InstrumentSearch {
    private(set) var items: [APICatalogItem] = []
    private(set) var loading = false
    private(set) var error: String?
    private var requestID = UUID()

    func search(_ query: String, using client: InstrumentSearching, debounce: Duration = .milliseconds(250)) async {
        let id = UUID(); requestID = id
        items = []; error = nil
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { loading = false; return }
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let results = try await client.searchInstruments(term)
            guard requestID == id, !Task.isCancelled else { return }
            items = results
        } catch is CancellationError {
            // Typing another character or leaving the screen cancels this request.
        } catch {
            guard requestID == id, !Task.isCancelled, !isRequestCancellation(error) else { return }
            self.error = error.localizedDescription
        }
    }
}
