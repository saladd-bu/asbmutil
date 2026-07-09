import Foundation
import ASBMUtilCore

@Observable
@MainActor
final class DeviceLookupViewModel {
    var serialInput = ""
    var importedSerials: [String] = []
    var results: [DeviceMdmResult] = []
    var isLoading = false
    var errorMessage: String?

    var serialNumbers: [String] {
        if !importedSerials.isEmpty {
            return importedSerials
        }
        return CSVParser.parseSerialTokens(serialInput)
    }

    var assignedCount: Int {
        results.filter { $0.assignedMdm != nil }.count
    }

    func lookup(client: APIClient) async {
        let serials = serialNumbers
        guard !serials.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        results.removeAll()

        do {
            results = try await client.lookupAssignedMdm(serials: serials)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Parse a CSV without committing it, for a preview step. Returns nil (and sets
    /// `errorMessage`) if the file can't be read or contains no serials.
    func readCSV(from url: URL) -> [String]? {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file"
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            return try CSVParser.readSerials(from: url)
        } catch {
            errorMessage = "CSV import failed: \(error.localizedDescription)"
            return nil
        }
    }

    func reset() {
        serialInput = ""
        importedSerials.removeAll()
        results.removeAll()
        errorMessage = nil
    }
}
