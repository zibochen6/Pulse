import SwiftUI

/// Tag removal only removes classification links; it never deletes tasks.
@MainActor
struct LocalTagSettingsView: View {
  @ObservedObject var controller: LocalTaskController
  let onEditingChanged: (Bool) -> Void

  @State private var editingTagID: UUID?
  @State private var proposedName = ""
  @State private var confirmsDeletion = false
  @State private var isSubmitting = false

  private var isBusy: Bool { isSubmitting || controller.isSaving }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Tags")
        .font(.system(size: 13, weight: .medium))
      Text(
        "Create tags from the tab bar’s + or a task’s tag field. Removing a tag moves its tasks to Todo."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let document = controller.document {
        if document.tags.isEmpty {
          Text("No tags yet")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(document.tags) { tag in
          tagContent(
            tag, index: document.tags.firstIndex(where: { $0.id == tag.id }) ?? 0,
            count: document.tags.count)
        }
      } else if controller.isLoading {
        ProgressView().controlSize(.mini)
      }
      if let errorMessage = controller.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear { onEditingChanged(editingTagID != nil) }
    .task {
      if controller.document == nil { await controller.refresh() }
    }
    .onChange(of: editingTagID) { onEditingChanged($0 != nil) }
    .onDisappear { onEditingChanged(false) }
    .onChange(of: controller.document?.tags.map(\.id)) { ids in
      if let editingTagID, ids?.contains(editingTagID) != true {
        closeEditor()
      }
    }
  }

  @ViewBuilder
  private func tagContent(_ tag: TaskTag, index: Int, count: Int) -> some View {
    if editingTagID == tag.id {
      VStack(alignment: .leading, spacing: 6) {
        if confirmsDeletion {
          Text("Remove “\(tag.name)”? Its tasks will move to Todo.")
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
          HStack {
            Button("Keep tag", action: closeEditor)
            Spacer()
            if isBusy { ProgressView().controlSize(.mini) }
            Button("Remove tag", role: .destructive) {
              guard !isBusy else { return }
              isSubmitting = true
              Task {
                defer { isSubmitting = false }
                if await controller.deleteTag(id: tag.id) { closeEditor() }
              }
            }
            .accessibilityIdentifier("confirmDeleteLocalTag.\(tag.id.uuidString)")
          }
        } else {
          TextField("Tag name", text: $proposedName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .accessibilityIdentifier("renameLocalTagField.\(tag.id.uuidString)")
            .onSubmit { saveName(tag) }
          HStack {
            Button("Cancel", action: closeEditor)
            Spacer()
            if isBusy { ProgressView().controlSize(.mini) }
            Button("Save") { saveName(tag) }
              .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .accessibilityIdentifier("saveLocalTagName.\(tag.id.uuidString)")
          }
        }
      }
      .buttonStyle(PulseActionButtonStyle())
      .font(.caption)
      .disabled(isBusy)
    } else {
      HStack(spacing: 8) {
        Image(systemName: "tag")
          .foregroundStyle(.secondary)
        Text(tag.name)
          .font(.system(size: 13))
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(0)
        Spacer(minLength: 4)
        // Reordering is offered here too, so the Settings list can be arranged
        // without going back to the tab bar. Icons keep the row inside the
        // 360 pt popover; the tab bar's context menu names the same two
        // commands in words.
        Button {
          moveTag(tag, to: index - 1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .buttonStyle(PulseIconButtonStyle())
        .disabled(isBusy || index == 0)
        .help("Move left")
        .accessibilityLabel("Move \(tag.name) left")
        .accessibilityIdentifier("moveLocalTagLeft.\(tag.id.uuidString)")
        Button {
          moveTag(tag, to: index + 1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .buttonStyle(PulseIconButtonStyle())
        .disabled(isBusy || index >= count - 1)
        .help("Move right")
        .accessibilityLabel("Move \(tag.name) right")
        .accessibilityIdentifier("moveLocalTagRight.\(tag.id.uuidString)")
        Button("Rename") {
          controller.dismissError()
          proposedName = tag.name
          confirmsDeletion = false
          editingTagID = tag.id
        }
        .buttonStyle(PulseActionButtonStyle())
        .accessibilityIdentifier("renameLocalTag.\(tag.id.uuidString)")
        Button("Remove", role: .destructive) {
          controller.dismissError()
          confirmsDeletion = true
          editingTagID = tag.id
        }
        .buttonStyle(PulseActionButtonStyle())
        .accessibilityIdentifier("deleteLocalTag.\(tag.id.uuidString)")
      }
      .font(.caption)
      .disabled(isBusy)
    }
  }

  private func saveName(_ tag: TaskTag) {
    guard !isBusy else { return }
    let name = proposedName
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      if await controller.renameTag(id: tag.id, name: name) { closeEditor() }
    }
  }

  private func moveTag(_ tag: TaskTag, to index: Int) {
    guard !isBusy, let tags = controller.document?.tags else { return }
    let clamped = max(0, min(index, tags.count - 1))
    guard clamped != tags.firstIndex(where: { $0.id == tag.id }) else { return }
    Task {
      _ = await controller.moveTag(id: tag.id, toIndex: clamped)
    }
  }

  private func closeEditor() {
    editingTagID = nil
    proposedName = ""
    confirmsDeletion = false
  }
}
