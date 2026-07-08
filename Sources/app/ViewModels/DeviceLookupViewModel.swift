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
        return serialInput
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    func importCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            importedSerials = try CSVParser.readSerials(from: url)
        } catch {
            errorMessage = "CSV import failed: \(error.localizedDescription)"
        }
    }

    func reset() {
        serialInput = ""
        importedSerials.removeAll()
        results.removeAll()
        errorMessage = nil
    }
}
