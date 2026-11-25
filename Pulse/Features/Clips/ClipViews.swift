import AppKit
import SwiftUI

struct ClipHomeButton: View {
  @ObservedObject var clips: ClipController
  let open: () -> Void
  let configure: () -> Void
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    let phase = clips.snapshot.phase
    let title = phase.isActive ? phase.title : PulseLocalization.string("Edit recording")
    Button {
      if clips.snapshot.phase.isActive {
        open()
      } else if clips.hasWorkspace {
        clips.start()
      } else {
        configure()
      }
    } label: {
      HStack(spacing: 5) {
        if clips.snapshot.phase == .running && !reduceMotion {
          ProgressView().controlSize(.mini).frame(width: 14)
        } else {
          Image(systemName: clips.snapshot.phase == .running ? "waveform" : "scissors")
            .frame(width: 14)
        }
        Text(phase == .checking ? PulseLocalization.string("Checking…") : title)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .buttonStyle(
      PulseActionButtonStyle(emphasis: .focusTimer(isRunning: clips.snapshot.phase.isActive))
    )
    .help("Edit the latest recording in Downloads")
    .accessibilityLabel(title)
    .accessibilityIdentifier("editRecordingButton")
    .contextMenu { Button("Last editing task", action: open) }
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) {
      ["editRecordingButton": $0]
    }
  }
}

struct ClipResultLink: View {
  @ObservedObject var clips: ClipController
  let open: () -> Void

  var body: some View {
    let state = clips.snapshot
    if state.phase == .noClip && state.folderURL == nil {
      Text(state.phase.title).font(.caption).foregroundStyle(PulseDesignTokens.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .pulsePaper(PulseDesignTokens.butterPaper)
        .padding(.horizontal, PulseDesignTokens.contentInset).padding(.bottom, 8)
    } else if !clips.isResultDone, state.phase != .idle,
      state.phase != .starting || !state.source.isEmpty
    {
      HStack(spacing: 8) {
        Button(action: open) {
          HStack(spacing: 6) {
            Text(
              state.phase.isActive
                ? PulseLocalization.string("clip." + (state.activity ?? "launch"))
                : state.phase.title
            )
            .lineLimit(1)
            .layoutPriority(1)
            Spacer(minLength: 6)
            Text(verbatim: state.source).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.right").accessibilityHidden(true)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("openClipResultButton")
        if clips.canMarkResultDone {
          Button("Done") { clips.markResultDone(id: state.id) }
            .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
            .fixedSize()
            .accessibilityIdentifier("markClipResultDoneButton")
        }
      }
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, clips.canMarkResultDone ? 4 : 8)
      .pulsePaper(PulseDesignTokens.butterPaper)
      .padding(.horizontal, PulseDesignTokens.contentInset).padding(.bottom, 8)
    }
  }
}

struct ClipDetailView: View {
  @ObservedObject var clips: ClipController
  let openSettings: () -> Void

  var body: some View {
    let state = clips.snapshot
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        PulseSection(
          title: state.phase.title, symbol: "scissors", paper: PulseDesignTokens.butterPaper
        ) {
          if !state.source.isEmpty {
            Text(state.source).font(.body.weight(.medium)).textSelection(.enabled)
          }
          if let model = state.model, let effort = state.effort {
            Text(verbatim: "\(model) · \(effort)").font(.caption).foregroundStyle(.secondary)
          }
          if state.phase.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let elapsed = max(0, Int(timeline.date.timeIntervalSince1970 - state.started))
              let silent = max(0, Int(timeline.date.timeIntervalSince1970 - state.updated))
              VStack(alignment: .leading, spacing: 5) {
                Text(activityTitle(state.activity)).font(.subheadline)
                Text(
                  PulseLocalization.format(
                    "Elapsed %@",
                    String(format: "%d:%02d", elapsed / 60, elapsed % 60)))
                if silent >= 60 {
                  Text(PulseLocalization.format("Last activity %lld min ago", Int64(silent / 60)))
                }
              }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
          }
          if let detail = state.detail, !detail.isEmpty {
            Text(PulseLocalization.string(detail)).font(.callout).textSelection(.enabled)
          }
        }
        ForEach(state.platforms, id: \.platform) { draft in
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(PulseLocalization.string(draft.platform)).fontWeight(.medium)
              Spacer()
              Text(PulseLocalization.string("clip." + draft.status))
                .foregroundStyle(
                  draft.status == "saved_verified"
                    ? PulseDesignTokens.success : PulseDesignTokens.muted)
            }
            if !draft.detail.isEmpty {
              Text(PulseLocalization.string(draft.detail)).font(.caption).foregroundStyle(
                .secondary)
            }
          }
          .padding(12)
          .pulsePaper()
        }
        let result = state.folderURL != nil ? state : clips.previousResult
        if let result {
          if result.id != state.id {
            Text("Previous result").font(.caption).foregroundStyle(.secondary)
          }
          HStack {
            if let folder = result.folderURL {
              Button("Open work folder") { NSWorkspace.shared.open(folder) }
                .buttonStyle(PulseActionButtonStyle())
            }
            if let review = result.reviewURL {
              Button("View review page") { NSWorkspace.shared.open(review) }
                .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
            }
          }
        }
        if state.phase == .failed || !clips.hasWorkspace {
          Button("Editing settings", action: openSettings)
            .buttonStyle(PulseActionButtonStyle())
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(PulseDesignTokens.contentInset)
    }.accessibilityIdentifier("clipTaskDetails")
  }

  private func activityTitle(_ key: String?) -> String {
    PulseLocalization.string("clip." + (key ?? "launch"))
  }
}

struct ClipSettingsView: View {
  @ObservedObject var clips: ClipController
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      LabeledContent("Model") {
        TextField("Model ID", text: $clips.model)
          .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
      }
      Picker("Reasoning effort", selection: $clips.effort) {
        ForEach(ClipController.efforts, id: \.self) { Text(verbatim: $0).tag($0) }
      }
      Divider()
      HStack {
        Text("Editing workspace")
        Spacer()
        Button("Choose folder…") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          if !clips.workspace.isEmpty { panel.directoryURL = URL(fileURLWithPath: clips.workspace) }
          if panel.runModal() == .OK, let url = panel.url { clips.workspace = url.path }
        }
        .buttonStyle(PulseActionButtonStyle())
      }
      if !clips.workspace.isEmpty {
        Text(verbatim: clips.workspace).font(.callout).textSelection(.enabled)
      }
      if !clips.hasWorkspace {
        Text("Choose a workspace containing the editing skill.").font(.callout).foregroundStyle(
          .secondary)
      } else {
        Text("Finished work is saved in the workspace’s output folder.").font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }
}
