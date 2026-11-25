import AppKit
import SwiftUI

@MainActor
struct QuickCopyView: View {
  @ObservedObject var controller: QuickCopyController
  let onEditingChanged: (Bool) -> Void

  @State private var search = ""
  @FocusState private var focus: Input?

  private enum Input: Hashable { case search, name, text }
  private var isEditing: Bool { focus == .search || controller.draft != nil }

  var body: some View {
    Group {
      if let draft = controller.draft {
        editor(for: draft)
      } else {
        list
      }
    }
    .font(.system(size: PulseDesignTokens.footnote))
    .foregroundStyle(PulseDesignTokens.ink)
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.bottom, PulseDesignTokens.contentInset)
    .onAppear { onEditingChanged(isEditing) }
    .onChange(of: isEditing) { onEditingChanged($0) }
    .onDisappear {
      onEditingChanged(false)
      controller.clearCopyFeedback()
    }
    .task { await controller.loadIfNeeded() }
  }

  private var list: some View {
    let rows = controller.filteredEntries(matching: search)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: PulseDesignTokens.gap) {
        HStack(spacing: PulseDesignTokens.gap) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(PulseDesignTokens.muted)
            .accessibilityHidden(true)
          TextField("Search by name", text: $search)
            .textFieldStyle(.plain)
            .focused($focus, equals: .search)
            .accessibilityIdentifier("quickCopySearch")
        }
        .padding(10)
        .pulsePaper(PulseDesignTokens.secondarySurface)

        Button {
          controller.beginAdding()
        } label: {
          Label("New entry", systemImage: "plus")
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .disabled(!controller.hasLoaded || controller.hasPendingWrite)
        .accessibilityIdentifier("newQuickCopyEntryButton")
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: PulseDesignTokens.gap) {
          if !controller.hasLoaded, controller.issue != .load {
            Label {
              Text("Loading entries")
            } icon: {
              PulseBusyGlyph(isBusy: controller.isLoading) { Image(systemName: "doc.on.doc") }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            }
            .foregroundStyle(PulseDesignTokens.muted)
            .padding(12)
          } else if controller.hasLoaded, rows.isEmpty {
            Text(
              LocalizedStringKey(
                controller.entries.isEmpty ? "No saved entries yet" : "No matching entries")
            )
            .foregroundStyle(PulseDesignTokens.muted)
            .padding(12)
          }

          ForEach(rows) { entry in
            QuickCopyRow(
              id: entry.id,
              name: entry.name,
              copied: controller.copiedEntryID == entry.id,
              managingDisabled: controller.hasPendingWrite,
              onCopy: { copy(entry.id) },
              onEdit: { controller.beginEditing(entry.id) },
              onDelete: { delete(entry.id) })
          }
        }
      }
      .accessibilityIdentifier("quickCopyList")
      issueBanner
    }
  }

  private func editor(for draft: QuickCopyEntry) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizedStringKey(controller.isEditingSavedEntry ? "Edit entry" : "New entry"))
        .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
        .accessibilityAddTraits(.isHeader)

      VStack(alignment: .leading, spacing: 6) {
        Text("Name").foregroundStyle(PulseDesignTokens.muted)
          .accessibilityHidden(true)
        TextField(
          "Name",
          text: Binding(
            get: { controller.draft?.name ?? draft.name },
            set: { controller.setDraftName($0, for: draft.id) })
        )
        .textFieldStyle(.plain)
        .focused($focus, equals: .name)
        .onSubmit { focus = .text }
        .padding(10)
        .pulsePaper(PulseDesignTokens.secondarySurface, radius: PulseDesignTokens.cornerSmall)
        .accessibilityIdentifier("quickCopyName")
      }
      .disabled(controller.hasPendingWrite)

      VStack(alignment: .leading, spacing: 6) {
        Text("Text to copy").foregroundStyle(PulseDesignTokens.muted)
          .accessibilityHidden(true)
        TextEditor(
          text: Binding(
            get: { controller.draft?.text ?? draft.text },
            set: { controller.setDraftText($0, for: draft.id) })
        )
        .font(.system(size: PulseDesignTokens.footnote, design: .monospaced))
        .scrollContentBackground(.hidden)
        .focused($focus, equals: .text)
        .padding(6)
        .pulsePaper(PulseDesignTokens.secondarySurface, radius: PulseDesignTokens.cornerSmall)
        .accessibilityLabel("Text to copy")
        .accessibilityIdentifier("quickCopyText")
      }
      .frame(maxHeight: .infinity)
      .disabled(controller.hasPendingWrite)

      issueBanner

      HStack(spacing: PulseDesignTokens.gap) {
        Spacer(minLength: 0)
        Button("Cancel") { controller.discardDraft() }
          .buttonStyle(PulseActionButtonStyle())
          .disabled(controller.hasPendingWrite)
          .accessibilityIdentifier("cancelQuickCopyEntryButton")
        Button(action: save) {
          Label {
            Text("Save")
          } icon: {
            PulseBusyGlyph(isBusy: controller.hasPendingWrite) {
              Image(systemName: "tray.and.arrow.down")
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
          }
        }
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!controller.canSaveDraft)
        .accessibilityIdentifier("saveQuickCopyEntryButton")
      }
    }
    .onAppear { focus = .name }
  }

  @ViewBuilder
  private var issueBanner: some View {
    if let issue = controller.issue {
      PulseErrorBanner(message: issue.message, accessibilityIdentifier: "quickCopyIssue") {
        switch issue {
        case .load:
          Button("Retry") { Task { await controller.loadIfNeeded() } }
        case .save:
          Button("Retry", action: save).disabled(!controller.canSaveDraft)
          Button("Dismiss") { controller.dismissIssue() }
        case .delete(let id):
          Button("Retry") { delete(id) }
          Button("Dismiss") { controller.dismissIssue() }
        case .copy(let id):
          Button("Retry") { copy(id) }
          Button("Dismiss") { controller.dismissIssue() }
        }
      }
    }
  }

  private func save() {
    guard (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return }
    guard let id = controller.draft?.id else { return }
    Task {
      guard controller.draft?.id == id, await controller.saveDraft() else { return }
      if !controller.filteredEntries(matching: search).contains(where: { $0.id == id }) {
        search = ""
      }
    }
  }

  private func delete(_ id: UUID) {
    Task { await controller.deleteEntry(id) }
  }

  private func copy(_ id: UUID) {
    guard controller.copy(id) else { return }
    NSAccessibility.post(
      element: NSApplication.shared, notification: .announcementRequested,
      userInfo: [
        .announcement: PulseLocalization.string("Copied"),
        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
      ])
  }
}

@MainActor
private struct QuickCopyRow: View {
  let id: UUID
  let name: String
  let copied: Bool
  let managingDisabled: Bool
  let onCopy: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @State private var hovered = false

  var body: some View {
    HStack(spacing: 4) {
      Button(action: onCopy) {
        HStack(spacing: PulseDesignTokens.gap) {
          Text(name)
            .font(.system(size: PulseDesignTokens.label, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          feedback
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: hovered))
      .onHover { hovered = $0 }
      .help(name)
      .accessibilityLabel(Text(name))
      .accessibilityHint(Text("Copy"))
      .accessibilityValue(copied ? Text("Copied") : Text(""))
      .accessibilityIdentifier("copyQuickCopyEntry.\(id.uuidString)")

      Menu {
        Button("Edit entry", action: onEdit)
        Button("Delete entry", role: .destructive, action: onDelete)
      } label: {
        Image(systemName: "ellipsis")
          .frame(width: 28, height: 28)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .tint(PulseDesignTokens.ink)
      .fixedSize()
      .disabled(managingDisabled)
      .accessibilityLabel(Text("Actions for \(name)"))
      .accessibilityIdentifier("quickCopyRowActions.\(id.uuidString)")
    }
    .padding(4)
    .pulsePaper(radius: PulseDesignTokens.cornerMedium)
  }

  private var feedback: some View {
    ZStack(alignment: .trailing) {
      // Both labels stay in the same trailing slot so a copy only changes paint.
      Label("Copied", systemImage: "checkmark")
        .labelStyle(.titleAndIcon)
        .foregroundStyle(PulseDesignTokens.success)
        .opacity(copied ? 1 : 0)
      Image(systemName: "doc.on.doc")
        .foregroundStyle(PulseDesignTokens.muted)
        .opacity(copied ? 0 : 1)
    }
    .font(.system(size: PulseDesignTokens.caption, weight: .semibold))
    .fixedSize()
    .pulseContentFeedback(copied)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}
