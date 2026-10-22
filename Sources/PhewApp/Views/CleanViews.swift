import PhewCore
import SwiftUI

struct ConfirmView: View {
    @Bindable var model: AppModel
    let plan: CleanPlan
    let back: Screen

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Clean \(count(plan.items.count, "item"))?", back: { model.screen = back })
            Divider()
            Scroll(maxHeight: 300) {
                VStack(spacing: 0) {
                    ForEach(plan.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.target.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                TierBadge(tier: item.target.tier)
                                Text(bytes(item.bytes)).foregroundStyle(.secondary)
                            }
                            if let note = item.note {
                                Text(note).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if item.target.tier == .dataLoss {
                                Text("Deletes data you can't get back.").font(.subheadline).foregroundStyle(Palette.red)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            if !plan.skipped.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skipped").fontWeight(.semibold)
                    ForEach(plan.skipped, id: \.item.id) { Text($0.reason).font(.subheadline) }
                }
                .foregroundStyle(Palette.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.orange.opacity(0.12))
            }
            if plan.needsAdmin {
                Text("You'll be asked for your Mac password.")
                    .font(.subheadline).foregroundStyle(Palette.purple)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            Text("Deleted for good, not moved to the Trash.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 8)
            HStack {
                Spacer()
                Button("Cancel") { model.screen = back }
                // Return cleans, except when something can't be got back: then it takes a click.
                Button("Clean \(bytes(plan.expectedBytes))") { model.confirm() }
                    .keyboardShortcut(plan.hasDataLoss ? nil : .defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(plan.hasDataLoss ? .red : .accentColor)
                    .disabled(plan.items.isEmpty)
            }
            .padding(12)
        }
    }
}

struct CleaningView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cleaning \(title)…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

struct ReceiptView: View {
    @Bindable var model: AppModel
    let receipt: Receipt

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle").font(.title).foregroundStyle(Palette.green)
                Text("Phew. \(bytes(receipt.measuredTotal)) freed.").font(.title3).fontWeight(.semibold)
                Text("Available \(bytes(receipt.freeBefore)) → \(bytes(receipt.freeAfter))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            Scroll(maxHeight: 300) {
                VStack(spacing: 0) {
                    ForEach(receipt.entries, id: \.itemID) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(entry.skippedReason == nil ? bytes(entry.measured) : "skipped")
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = entry.skippedReason {
                                Text(reason).font(.subheadline).foregroundStyle(Palette.orange)
                            }
                            ForEach(entry.failures.prefix(5), id: \.self) {
                                Text($0).font(.subheadline).foregroundStyle(Palette.red).lineLimit(2)
                            }
                            if entry.failures.count > 5 {
                                Text("and \(entry.failures.count - 5) more").font(.subheadline).foregroundStyle(Palette.red)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { model.screen = .home }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}
