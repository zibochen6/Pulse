# Codex interactive requests in Pulse: feasibility study

Date: 2026-09-29. This is a protocol and local-environment study, not a Pulse feature release.

## Answer for the current desktop workflow

**Directly answering an existing ChatGPT/Codex desktop request from Pulse is not verified on this machine.** The desktop currently owns an app-server connection that Pulse cannot attach to through an observed public endpoint. A separate, Pulse-managed app-server session **did** accept a real structured answer and continue its original turn. That result does not transfer control of an existing desktop session.

The current evidence supports the category **“direct answer verified only in a self-managed test session.”** For the user's existing desktop sessions, the supported direct-answer category remains **“cannot confirm.”** Built-in desktop question and permission notifications already provide some awareness, subject to the user's notification settings. A public, precise deep link to an individual pending request was not established. No ordinary notification or generic app launch should be described as a direct-answer solution.

## 1. Local environment and existing Pulse boundary

| Item | Verified observation |
| --- | --- |
| Host | macOS 27.0 (26A428), arm64 |
| Desktop | ChatGPT desktop bundle version `26.924.22138`, build `11645`, running |
| CLI used by shell | Bundled executable `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`; `codex-cli 0.158.0-alpha.2.1` |
| Desktop process | The running desktop has a bundled Codex CLI child process using `app-server`. Its inspected command did not specify a Unix or TCP listener; the documented default is stdio. |
| Shared control endpoint | The CLI's default app-server control socket was absent. `codex app-server daemon version` failed to connect because that socket did not exist. No daemon was started or restarted. |
| Repository | Existing `codex/pulse-task-first-home` branch, clean at the start; no branch switch, reset, or changes to application code. |

The installed CLI advertises `app-server`, `daemon`, `proxy`, `generate-json-schema`, and transports `stdio://`, `unix://`, and `ws://`. Its `--experimental` schema was generated in a temporary directory. The local schema includes `item/tool/requestUserInput`, `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, and `serverRequest/resolved`. The generated `ToolRequestUserInputParams` requires `threadId`, `turnId`, `itemId`, `questions`, and `isBlocking`; a client reply has an `answers` map keyed by question ID. The command approval request requires `threadId`, `turnId`, `itemId`, and `startedAtMs`; its response contains a structured `decision`. These are protocol capabilities of this CLI version, not proof that another client's pending request can be answered.

Pulse currently launches **its own short-lived** `codex app-server --listen stdio://` process, completes `initialize` / `initialized`, calls `account/rateLimits/read`, and terminates that process. See [`CodexAppServerTransport.swift`](../Pulse/Features/Usage/Providers/CodexAppServerTransport.swift) and [`CodexProvider.swift`](../Pulse/Features/Usage/Providers/CodexProvider.swift). The same-account quota result does not connect Pulse to desktop turn events. Pulse's menu entry uses `NSStatusItem` and a transient, mouse-dismissed `NSPopover`; see [`PulseAppDelegate.swift`](../Pulse/App/PulseAppDelegate.swift) and [`PopoverHoverController.swift`](../Pulse/App/PopoverHoverController.swift). That popover lifecycle is unsuitable for a user who must read an approval and type an answer.

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server) describes the transports, initialization, thread/turn/item lifecycle, and approval requests. The observed desktop topology has no attachable control endpoint. Starting a separate daemon would create a different service instance unless the desktop is independently proven to share it. We did not start one or change the desktop launch configuration.

## 2. What the native client already provides

[OpenAI's Notifications documentation](https://learn.chatgpt.com/docs/notifications) describes separate desktop controls for turn-completion, permission, and question notifications, an Activity view for chats needing response, and a floating pet that can show “Needs input.” These may solve the awareness part of the request without Pulse. The documentation does not establish a general-purpose notification form that can answer every approval, free-text prompt, or plan confirmation in place.

This study did not read the user's notification preferences or macOS authorization status. Desktop UI automation for the current app was refused by the available computer-use tool, so actual notification delivery, a click-through destination, and any in-notification action remain **unverified locally**. The user can inspect ChatGPT Settings → Notifications and macOS notification permission; changing them was outside this study.

## 3. Distinct “needs user” events

| Situation | Signal to use | Return path | Verification here |
| --- | --- | --- | --- |
| A. Command execution approval | `item/commandExecution/requestApproval` with request ID, thread/turn/item identity, command or network context, cwd, reason, and offered decisions | JSON-RPC response to that exact server request; `decision` must be one of the offered choices | Present in local schema and official protocol; no live approval was triggered by the isolated tests |
| A. File-change approval | `item/fileChange/requestApproval`, associated proposed `fileChange` item, reason and optional grant root | Structured file-change decision on the same request ID | Schema and protocol only |
| A. Explicit permission request | `item/permissions/requestApproval` with requested filesystem/network subset | Return only the user's granted subset and an explicit scope | Schema and protocol only |
| B. Structured choice | `item/tool/requestUserInput` with `questions`, original option labels, question IDs and request ID | `answers[questionId].answers` on the matching JSON-RPC request | **Real self-managed request, answer, resolution, and continued turn verified** |
| C. Free text | The same `item/tool/requestUserInput` shape when the question permits text or an “Other” answer | The same keyed `answers` object, preserving the user's exact text | Attempted; model behavior did not yield a clean free-text-only success case |
| D. Plan execution confirmation | Final `plan` item and completed plan turn; desktop may then present “start implementing” UI | Requires an explicit user action/new turn established by the desktop client; **not** the command approval response | Self-managed plan item and completed turn observed; no approval server request appeared. Desktop button flow not tested |
| E. Assistant prose asks a question | An `agentMessage` item only | A later user message/turn if the user chooses to reply | No structured pending request or approval ID; do not auto-popup as an approval |
| F. Normal completion | `turn/completed` with completed status | None | Observed; completion alone does not mean input is needed |

For A, the [official App Server approval sequence](https://learn.chatgpt.com/docs/app-server#approvals) gives `serverRequest/resolved` and the final item lifecycle after a decision. `serverRequest/resolved` can also mean a request was cleared, so a client must reconcile the final item and turn state before telling the user that the original work continued. Network approvals can lack a useful shell command preview; show the host/protocol and actual permission context instead. For B/C, the local schema's question IDs and `answers` structure were checked before sending a test reply. A question mark in prose, `turn/plan/updated`, and `turn/completed` are not substitutes for a live server request.

## 4. Access paths compared

| Path | What it can provide | Boundary and present decision |
| --- | --- | --- |
| A. Native desktop | Permission/question notifications and Activity “needs input” list | Best immediate awareness option. Local notification settings and exact actions remain unverified; it is not Pulse's direct-answer card. |
| B. Hooks | `PermissionRequest` can see the approval tool and input, return allow/deny, or make no decision; matching hooks run concurrently and deny wins. | Only covers approval categories that actually invoke that hook. It is not a documented general answer route for structured questions or plan buttons. Non-managed hooks require explicit trust. No hook was installed, trusted, or tested in the desktop. See [official Hooks documentation](https://learn.chatgpt.com/docs/hooks). |
| C. Shared App Server | A second client could use the documented bidirectional protocol **if** the desktop and Pulse were proven to connect to the same reachable service and request ownership/routing were verified. | Current desktop has no observed shared endpoint. `thread/list`, matching IDs, or saved logs cannot prove same-instance control. Do not resume an active desktop thread just to subscribe. Stop here for existing desktop requests until a supported shared connection is demonstrated. |
| D. Pulse-managed session | Pulse owns an app-server connection and receives its own server requests. | Real structured answer verified below. Making users start all work through Pulse would change the product workflow and needs a separate decision. |
| E. Precise open / Accessibility | Could be a fallback if a public, stable destination for an exact thread/request is established. | No public pending-request deep link was verified. Accessibility would need user-granted permission, confirmation of target thread and request, and version-specific testing. Never use fixed coordinates or blind approval keystrokes. |

The CLI supports a managed local daemon and a proxy, and [its open-source daemon README](https://github.com/openai/codex/blob/main/codex-rs/app-server-daemon/README.md) describes an experimental shared control socket. This is a possible *future test topology*, not evidence that the current desktop uses it. We did not change global configuration, launch a daemon, or restart desktop sessions.

## 5. Isolated protocol experiments

All experiments used a disposable directory, the **installed local CLI**, a short model turn, and a temporary stdio client. They did not inspect authentication files, print raw private responses, alter Pulse, or operate a user's existing session. The synthetic question and answer were chosen solely for the test. Temporary scripts remained outside the repository; the evidence below is sanitized.

| Gate / attempt | Observation | Conclusion |
| --- | --- | --- |
| Capture a structured request | The app-server emitted `item/tool/requestUserInput` with one question and the expected `threadId`, `turnId`, `itemId`, options, and JSON-RPC request ID. | Gate 1 passed for a **self-managed** session. |
| Return the selected answer | The client sent `answers[questionId].answers = ["Blue"]` as the response to that request ID. The server emitted `serverRequest/resolved`; the final assistant item contained the synthetic continuation marker and `turn/completed` had `status: completed`. | Gate 2 passed for that same self-managed session. This was a live model/protocol exchange, not a fixture or mocked UI. |
| Permission approval attempt | With `on-request` / read-only and a harmless temporary marker command, and then with an explicit request for escalation, no approval server request was emitted. A further `untrusted` policy attempt likewise completed without such a request. | **Not verified.** Marker creation proves a command ran, not that user approval was captured or replayed. The current [permissions guide](https://learn.chatgpt.com/docs/agent-approvals-security) says `untrusted` is no longer supported despite its appearance in this CLI's generated schema; that attempt must not be taken as a supported policy test. |
| Free-text attempt | One model run emitted a question with options despite the free-text instruction. A subsequent run completed without a request. | A pure free-text request and answer remain unverified. |
| Plan confirmation attempt | A plan-mode turn emitted a final `plan` item containing text and completed normally, with no server-initiated approval request. | The self-managed protocol did not expose a Plan “start implementing” approval in that test. Desktop UI handling remains unverified. |

The test client answered only its own synthetic request after checking the thread, turn, question, and offered option. No command or plan was silently approved. Because the local approval attempt failed to produce a request, an approval debug card was **not** built: Gate 3 depends on Gates 1 and 2 for that event. A real request card for the structured-question case could be the next isolated experiment, but it would still only prove self-managed sessions.

## 6. Existing desktop versus self-managed sessions

The self-managed test client created the thread and held the stdio transport receiving its requests. The desktop process owns a separate app-server connection. The observed default control socket was absent; `daemon version` could not connect. The current Pulse quota reader also creates a separate short-lived process. Shared account state and persisted thread history can explain why both processes know of the same account or thread metadata; they do not establish live request delivery to Pulse.

We did not create or manipulate a desktop test chat. A real desktop request could not be observed through the supported Pulse-side endpoint in this topology, and the available UI automation tool refused access to the app. Therefore **no desktop request was captured or answered from Pulse**, no “original desktop session continued” result exists, and no precise pending-request navigation was established. This is a limitation of the current evidence and observed topology, not a claim that every future Codex version lacks such an interface.

## 7. Minimum product shape if the transport gate later passes

First prove with a **new, disposable desktop test chat** that Pulse can attach to the *same* server instance, receive a fresh structured request and an approval, answer by exact request ID, observe the desktop update, detect the desktop answering first, and reconnect without replay. A server instance identifier plus connection, thread, turn, item, request, and question identifiers should scope pending state; never route by title, project name, “latest request,” or an assumption that session ID equals thread ID.

Only after that gate passes, prototype one floating `NSPanel` for the current request and a reopenable queue. Show project label, real chat title or available ID, exact request type/content/options, explicit text field when offered, and the original-operation context. For command approval show the command or managed-network destination, cwd, requested scope, and reason. For Plan confirmation show the actual final plan and a separately verified action. Keep the panel stable while reading or typing; appearing must not take keyboard focus. “Hide for now” preserves the pending request. Deduplicate requests; disable stale ones; show `sending`, `confirmed by server`, and `unknown outcome` separately. On disconnect or lost acknowledgment, reconcile server state before any retry, especially for approvals. Never auto-select, auto-approve, broaden permission, or treat timeout as consent.

A macOS notification can announce a short request or reopen the pending queue. It cannot be assumed to carry arbitrary choices, long commands, a full plan, or a free-text form. The `NSPanel` is the candidate for complete decisions; it requires tests for multiple monitors, fullscreen apps, focus, lock screen, and notification denial. Do not expose sensitive content or an approval action on a locked screen. Do not reuse the existing popover's 400 ms hover dismissal. [Apple's NSPanel](https://developer.apple.com/documentation/appkit/nspanel) and [User Notifications](https://developer.apple.com/documentation/usernotifications) are the platform APIs to assess in the later UI prototype.

## 8. Stop conditions and next smallest task

1. **Desktop attachment gate:** identify a documented or otherwise supported local endpoint for the desktop's actual app-server instance. Show two-client connection and request routing with a disposable chat. If absent, stop the direct-answer implementation for current desktop chats.
2. **Request/response gate:** in that disposable desktop chat, separately capture and reply to one structured question and one harmless approval, proving the original desktop UI leaves its pending state. If a request is not delivered to Pulse, stop; do not infer success from thread history or a self-managed process.
3. **Plan gate:** inspect the desktop's actual Plan action. If it is a client-side new turn rather than a server approval request, design and test that as a distinct action; do not display a fabricated approval button.
4. **Fallback gate:** if direct answering remains unavailable, verify a public exact-chat destination. If none exists, offer only native notifications/Activity guidance or a clearly labelled ordinary reminder. Do not claim precise positioning or direct handling.

No full notification system, background service, global Hook, accessibility controller, provider, or task UI should be built from the present evidence. The present study made no persistent Codex configuration changes. A later Hook or shared-daemon experiment must show its exact configuration, trust implications, impact on currently running sessions, and rollback before any changes are made.

## 9. Evidence and maintenance costs

- [Codex App Server](https://learn.chatgpt.com/docs/app-server): protocol, transports, schema generation, lifecycle events, approvals, and `thread/read` versus resume.
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks): event scope, trust review, concurrent Hook behavior, and `PermissionRequest` decisions.
- [ChatGPT Notifications](https://learn.chatgpt.com/docs/notifications): desktop permission/question notifications, Activity, and pet status.
- [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security): current approval-policy guidance.
- [Open-source App Server daemon README](https://github.com/openai/codex/blob/main/codex-rs/app-server-daemon/README.md): experimental managed control socket and lifecycle.
- Local CLI `--help`, generated version-specific JSON schemas, process parent/transport check, absent default socket, and the sanitized experiment outcomes above. No credentials, private chat body, or personal project paths were recorded.

The app-server protocol and experimental fields may change with a Codex update. Hooks have a separate trust lifecycle and may not run identically in desktop, CLI, and IDE clients. Cross-client ownership, reconnection, and ambiguous acknowledgments carry the highest correctness risk. A local listening endpoint requires explicit same-user access controls or authentication; “localhost” alone is not an authorization boundary. A desktop UI automation fallback has ongoing compatibility and permission cost and cannot safely approve when the target request cannot be confirmed.

## 10. Verification status

| Evidence level | Result |
| --- | --- |
| Mock or fixture | None used as proof of a successful interaction. |
| Live protocol, self-managed | Structured question capture → keyed answer → resolution → final continuation **passed**. Permission and pure free text **not verified**. Plan item/completion **observed**, without an approval request. |
| Existing desktop app | Process and transport topology **observed**. Direct question/approval reply, native notification delivery, Plan button semantics, and exact request navigation **not verified**. |

Only this report was added to Pulse. No application code, test suite, persistent service, or global Codex configuration was changed. There was no build requirement for a documentation-only investigation; repository diff and privacy checks are the appropriate local validation.
