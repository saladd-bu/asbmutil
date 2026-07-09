import SwiftUI
import AppKit
import ASBMUtilCore

extension DeviceAttributes {
    var sortProductFamily: String { productFamily ?? "" }
    var sortProductType: String { productType ?? "" }
    var sortStatus: String { status ?? "" }
    var sortPurchaseSourceType: String { purchaseSourceType ?? "" }
    var sortOrderNumber: String { orderNumber ?? "" }

    /// Numeric rank so "64GB" < "256GB" < "1TB" instead of lexicographic order.
    var sortCapacityRank: Double {
        guard let raw = deviceCapacity else { return -1 }
        let upper = raw.uppercased()
        let digits = upper.filter { $0.isNumber || $0 == "." }
        let value = Double(digits) ?? 0
        if upper.contains("TB") { return value * 1024 }
        if upper.contains("GB") { return value }
        if upper.contains("MB") { return value / 1024 }
        return value
    }

    var sortOrderDate: Date { Self.parseDate(orderDateTime) }
    var sortUpdatedDate: Date { Self.parseDate(updatedDateTime) }

    /// Sentinel for missing dates so empty rows sort to the bottom on ascending order.
    private static let missingDate = Date.distantPast

    static func parseDate(_ s: String?) -> Date {
        guard let s, !s.isEmpty else { return missingDate }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        return missingDate
    }

    /// A human-readable date for display, or "" when absent/unparseable. Keeps the
    /// table from showing raw ISO-8601 timestamps like `2024-06-01T12:00:00.000Z`.
    static func displayDate(_ s: String?) -> String {
        let d = parseDate(s)
        guard d != missingDate else { return "" }
        return d.formatted(.dateTime.year().month().day())
    }

    /// A human-readable date + time for display, or "" when absent/unparseable.
    static func displayDateTime(_ s: String?) -> String {
        let d = parseDate(s)
        guard d != missingDate else { return "" }
        return d.formatted(.dateTime.year().month().day().hour().minute())
    }
}

struct DeviceTable: View {
    let devices: [DeviceAttributes]
    @Binding var selection: Set<String>
    @State private var sortOrder: [KeyPathComparator<DeviceAttributes>] = [
        KeyPathComparator(\.serialNumber)
    ]
    @State private var sortedDevices: [DeviceAttributes] = []

    var body: some View {
        Table(sortedDevices, selection: $selection, sortOrder: $sortOrder) {
            group1
            group2
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Copy Serial Number\(ids.count == 1 ? "" : "s")") { copySerials(ids) }
                .disabled(ids.isEmpty)
            Button("Copy as Rows (TSV)") { copyRows(ids) }
                .disabled(ids.isEmpty)
        }
        .onCopyCommand { copyItemProviders(selection) }
        .onAppear { sortedDevices = devices.sorted(using: sortOrder) }
        .onChange(of: devices) { _, new in
            sortedDevices = new.sorted(using: sortOrder)
        }
        .onChange(of: sortOrder) { _, new in
            sortedDevices = devices.sorted(using: new)
        }
    }

    // MARK: - Copy

    private func rows(for ids: Set<String>) -> [DeviceAttributes] {
        sortedDevices.filter { ids.contains($0.serialNumber) }
    }

    private func copySerials(_ ids: Set<String>) {
        let text = rows(for: ids).map(\.serialNumber).joined(separator: "\n")
        writeToPasteboard(text)
    }

    private func copyRows(_ ids: Set<String>) {
        writeToPasteboard(tsv(for: ids))
    }

    /// ⌘C support: hand the standard Copy command the selected serials as text.
    private func copyItemProviders(_ ids: Set<String>) -> [NSItemProvider] {
        guard !ids.isEmpty else { return [] }
        return [NSItemProvider(object: rows(for: ids).map(\.serialNumber).joined(separator: "\n") as NSString)]
    }

    private func tsv(for ids: Set<String>) -> String {
        rows(for: ids).map { d in
            [d.serialNumber, d.displayModel, d.productFamily ?? "", d.productType ?? "",
             d.status ?? "", d.deviceCapacity ?? "", d.purchaseSourceType ?? "",
             d.orderNumber ?? "", DeviceAttributes.displayDate(d.orderDateTime),
             DeviceAttributes.displayDate(d.updatedDateTime)].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private func writeToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @TableColumnBuilder<DeviceAttributes, KeyPathComparator<DeviceAttributes>>
    private var group1: some TableColumnContent<DeviceAttributes, KeyPathComparator<DeviceAttributes>> {
        TableColumn("Serial Number", value: \.serialNumber) { (d: DeviceAttributes) in
            Text(d.serialNumber).fontDesign(.monospaced)
        }
        .width(min: 110, ideal: 140)

        TableColumn("Model", value: \.displayModel) { (d: DeviceAttributes) in
            Text(d.displayModel)
        }
        .width(min: 120, ideal: 180)

        TableColumn("Product Family", value: \.sortProductFamily) { (d: DeviceAttributes) in
            Text(d.productFamily ?? "")
        }
        .width(min: 80, ideal: 110)

        TableColumn("Product Type", value: \.sortProductType) { (d: DeviceAttributes) in
            Text(d.productType ?? "")
        }
        .width(min: 90, ideal: 120)

        TableColumn("Status", value: \.sortStatus) { (d: DeviceAttributes) in
            StatusBadge(status: d.status ?? "")
        }
        .width(min: 100, ideal: 130)
    }

    @TableColumnBuilder<DeviceAttributes, KeyPathComparator<DeviceAttributes>>
    private var group2: some TableColumnContent<DeviceAttributes, KeyPathComparator<DeviceAttributes>> {
        TableColumn("Storage", value: \.sortCapacityRank) { (d: DeviceAttributes) in
            Text(d.deviceCapacity ?? "")
        }
        .width(min: 60, ideal: 80)

        TableColumn("Source", value: \.sortPurchaseSourceType) { (d: DeviceAttributes) in
            Text(d.purchaseSourceType ?? "")
        }
        .width(min: 60, ideal: 100)

        TableColumn("Order Number", value: \.sortOrderNumber) { (d: DeviceAttributes) in
            Text(d.orderNumber ?? "")
        }
        .width(min: 80, ideal: 130)

        TableColumn("Order Date", value: \.sortOrderDate) { (d: DeviceAttributes) in
            Text(DeviceAttributes.displayDate(d.orderDateTime))
        }
        .width(min: 80, ideal: 120)

        TableColumn("Updated", value: \.sortUpdatedDate) { (d: DeviceAttributes) in
            Text(DeviceAttributes.displayDate(d.updatedDateTime))
        }
        .width(min: 80, ideal: 120)
    }
}
