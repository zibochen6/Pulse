# Verification

- Xcode 27.0 on macOS 27.0.1, arm64. Full suite with `-testLanguage en -testRegion US`: 264 passed, 2 skipped, 0 failed.
- With the system's Chinese language, the same six existing tests failed in this checkout and in an isolated copy of the starting commit. The five focus timer tests passed.
- The isolated 12-second native build verified starting from Home, closing and reopening the popover during the session, preserving the status item title, and returning to idle after the closed-popover timer completed. AppKit accepted exactly one Glass playback request.
- The Chinese native build verified the start and cancel labels and returned to idle immediately. No chime was submitted after the canceled timer's original deadline.
- A simulated overdue wake verifies one completion. Physical sleep/wake was not exercised. The installed Pulse was not replaced.
- Swift formatting lint, both localization property list checks, and `git diff --check` passed.

## Release 0.1.10 (build 14)

- The release gate ran 266 tests, with 264 passed, 2 skipped, and 0 failures.
- The Apple Development-signed arm64/x86_64 app passed signature, mounted DMG,
  ZIP and SHA-256 verification. The installed build is 0.1.10.
- A signed copy of the previous installed 0.1.9 build, in an isolated
  Applications subdirectory, checked its localhost feed through Settings.
  The genuine updater fetched the release ZIP and checksum, staged the
  update, restarted on request, and relaunched that copy as 0.1.10. The
  upgraded executable matched the installed release byte-for-byte. The
  upgraded app started and canceled a focus session without changing the
  menu bar title. The primary installation was relaunched afterwards.
- The unauthenticated GitHub API was rate-limited on this network. The
  end-to-end update rehearsal used a loopback feed and the release ZIP.
- GitHub marked v0.1.10 latest. All four remotely reported asset sizes and
  SHA-256 digests matched the verified archives and checksum files. The
  public update ZIP is the one used in rehearsal (SHA-256
  `fade3775300d0f27abb545ff486148b4d3ecec69b772b1f6777f0b6fa660ca9c`).
