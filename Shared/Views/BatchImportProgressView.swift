import SwiftUI

/// Per-file progress sheet shown while importing multiple EPUBs at once
/// (typically via drag-and-drop). Each row reflects pending/importing/
/// succeeded/failed status for one file.
struct BatchImportProgressView: View {
    let items: [BatchImportItem]

    private var succeededCount: Int {
        items.filter { if case .succeeded = $0.status { return true } else { return false } }.count
    }
    private var failedCount: Int {
        items.filter { if case .failed = $0.status { return true } else { return false } }.count
    }
    private var totalDone: Int { succeededCount + failedCount }
    private var allDone: Bool { totalDone >= items.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if allDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(allDone ? "Imported \(succeededCount) of \(items.count)"
                                 : "Importing \(items.count) book\(items.count == 1 ? "" : "s")…")
                        .font(.headline)
                    if failedCount > 0 {
                        Text("\(failedCount) failed")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        BatchImportRow(item: item)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(20)
        .frame(width: 440)
        .cruxGlassFloating(cornerRadius: 14)
    }
}

private struct BatchImportRow: View {
    let item: BatchImportItem

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)
            Text(item.fileName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if case .failed(let reason) = item.status {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .importing:
            ProgressView().controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}
