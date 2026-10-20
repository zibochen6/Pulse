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
      Text("Create tags from the tab bar’s + or a task’s tag field. Removing a tag keeps its tasks.")
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
          tagContent(tag)
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
  private func tagContent(_ tag: TaskTag) -> some View {
    if editingTagID == tag.id {
      VStack(alignment: .leading, spacing: 6) {
        if confirmsDeletion {
          Text("Remove “\(tag.name)” from all tasks? Tasks will be kept.")
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
        Spacer()
        Button("Rename") {
          controller.dismissError()
          proposedName = tag.name
          confirmsDeletion = false
          editingTagID = tag.id
        }
        .accessibilityIdentifier("renameLocalTag.\(tag.id.uuidString)")
        Button("Remove", role: .destructive) {
          controller.dismissError()
          confirmsDeletion = true
          editingTagID = tag.id
        }
        .accessibilityIdentifier("deleteLocalTag.\(tag.id.uuidString)")
      }
      .buttonStyle(PulseActionButtonStyle())
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

  private func closeEditor() {
    editingTagID = nil
    proposedName = ""
    confirmsDeletion = false
  }
}
