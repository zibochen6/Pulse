import SwiftUI

/// One tag manager is reused by the quick panel and Settings. All edit intents
/// belong to the app-owned presentation, so changing categories never loses input.
@MainActor
struct LocalTagSettingsView: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  var onEditingChanged: (Bool) -> Void = { _ in }
  var onReturnToDraft: () -> Void = {}
  var onSelectTag: ((UUID?) -> Void)?
  @FocusState private var searchFocused: Bool

  private var isEditing: Bool { searchFocused || presentation.tagIntent != nil }

  private var tags: [TaskTag] { controller.document?.tags ?? [] }
  private var filteredTags: [TaskTag] {
    let query = presentation.tagSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? tags : tags.filter { $0.name.localizedStandardContains(query) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search tags", text: $presentation.tagSearch)
            .focused($searchFocused)
            .textFieldStyle(.plain).accessibilityIdentifier("searchLocalTagsField")
        }
        .padding(10)
        .pulsePaper(PulseDesignTokens.secondarySurface)
        Button {
          controller.dismissError()
          presentation.beginCreatingTag()
        } label: {
          Label("New tag", systemImage: "plus")
        }
        .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
        .disabled(controller.isSaving || presentation.tagIntent != nil)
        .accessibilityIdentifier("createManagedTagButton")
      }
      if presentation.tagIntent != nil {
        LocalTagEntry(
          controller: controller, presentation: presentation, onReturnToDraft: onReturnToDraft
        )
        .padding(.horizontal, -PulseDesignTokens.contentInset)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if presentation.tagSearch.isEmpty {
            HStack(spacing: 10) {
              Image(systemName: "tray").foregroundStyle(PulseDesignTokens.accent)
              VStack(alignment: .leading, spacing: 2) {
                Text("Todo").font(.system(size: 13, weight: .medium))
                Text("Default list · Cannot be renamed or removed")
                  .font(.system(size: 12)).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              if let onSelectTag {
                Button("Open") { onSelectTag(nil) }.buttonStyle(PulseActionButtonStyle())
              }
            }
            .padding(12)
            .pulsePaper(PulseDesignTokens.taskPaper)
          }
          if controller.isLoading {
            ProgressView("Loading tags").font(.system(size: 12)).padding()
          } else if filteredTags.isEmpty {
            Text(
              LocalizedStringKey(
                tags.isEmpty ? "Create your first tag to organize tasks." : "No matching tags")
            )
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(12)
          }
          ForEach(filteredTags) { tag in tagRow(tag) }
        }
      }
      .accessibilityIdentifier("localTagManagerList")
      if let message = controller.errorMessage {
        HStack {
          Text(message).font(.system(size: 12)).foregroundStyle(PulseDesignTokens.destructive)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Button("Dismiss") { controller.dismissError() }
            .buttonStyle(PulseActionButtonStyle())
        }
      }
      LocalDeletionUndoBar(controller: controller, presentation: presentation)
    }
    .font(.system(size: 13))
    .onAppear { onEditingChanged(isEditing) }
    .onChange(of: isEditing) { onEditingChanged($0) }
    .onDisappear { onEditingChanged(false) }
    .task { if controller.document == nil { await controller.refresh() } }
    .onChange(of: controller.document?.tags) { tags in
      if let tags {
        presentation.reconcileTags(tags)
        presentation.reconcileTagOrder(tags)
      }
    }
  }

  private func tagRow(_ tag: TaskTag) -> some View {
    let index = tags.firstIndex(where: { $0.id == tag.id }) ?? 0
    let count = controller.document?.tasks.filter { $0.tagIDs.contains(tag.id) }.count ?? 0
    return HStack(alignment: .center, spacing: 10) {
      Image(systemName: "tag")
        .font(.system(size: 13))
        .foregroundStyle(PulseDesignTokens.tagColor(for: tag.id))
        .frame(width: 28, height: 28)
        .background(PulseDesignTokens.secondarySurface, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        if let onSelectTag {
          Button {
            onSelectTag(tag.id)
          } label: {
            Text(tag.name).font(.system(size: 13, weight: .medium))
              .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          }
          .buttonStyle(.plain)
        } else {
          Text(tag.name).font(.system(size: 13, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(PulseLocalization.format(count == 1 ? "%lld task" : "%lld tasks", count))
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button("Rename") {
        controller.dismissError()
        presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
      }
      .buttonStyle(PulseActionButtonStyle())
      .accessibilityIdentifier("renameLocalTag.\(tag.id.uuidString)")
      Menu {
        Button("Move Up") { moveTag(tag, to: index - 1) }.disabled(index == 0)
        Button("Move Down") { moveTag(tag, to: index + 1) }.disabled(index == tags.count - 1)
        Divider()
        Button("Delete list…", role: .destructive) {
          controller.dismissError()
          presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
        }
        .accessibilityIdentifier("deleteLocalTag.\(tag.id.uuidString)")
      } label: {
        Image(systemName: "ellipsis").frame(width: 28, height: 28)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("Actions for \(tag.name)")
    }
    .padding(12)
    .pulsePaper()
    .disabled(controller.isSaving || presentation.tagIntent != nil)
    .accessibilityIdentifier("managedLocalTag.\(tag.id.uuidString)")
  }

  private func moveTag(_ tag: TaskTag, to index: Int) {
    guard !controller.isSaving else { return }
    Task { _ = await controller.moveTag(id: tag.id, toIndex: index) }
  }
}
