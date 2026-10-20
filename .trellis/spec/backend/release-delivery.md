# macOS preview release delivery contract

## 1. Scope / Trigger

Use when the user explicitly requests a Pulse build, local app replacement, source publication, or GitHub downloadable release, normally through `scripts/release.sh`. Ordinary implementation does not authorize replacing an installed app or publishing a release; use the actual user-authorized delivery scope.

## 2. Signatures

```sh
./scripts/release.sh <version>   # single release path: tests, bump, build, sign, package, install, publish
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release -destination 'generic/platform=macOS' -derivedDataPath <release-dir>/DerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build
codesign --force --sign <existing-development-identity> --timestamp=none <release-app>
codesign --verify --deep --strict <release-app>
lipo -archs <release-app>/Contents/MacOS/Pulse
ditto -c -k --keepParent <release-app> <release-dir>/Pulse-<version>.zip
shasum -a 256 <release-dir>/Pulse-<version>.zip > <release-dir>/Pulse-<version>.zip.sha256
gh release create <version-tag> <dmg> <dmg-sha256> <zip> <zip-sha256> --repo zibochen6/Pulse --verify-tag --title <title> --notes-file <release-notes>
```

`project.yml` owns `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; the generated Xcode project and app Info.plist must agree. Keep `dev.zibochen.Pulse`, macOS 13 minimum, and both arm64/x86_64 architectures.

## 3. Contracts

- Follow the existing preview channel: Apple Development signing with the available identity used by the installed app. Check the signer/team rather than silently switching identity. Never claim Developer ID signing or notarization, change Gatekeeper, or assume a development-signed preview is fresh-machine accepted.
- The exact signed app is the payload for local installation, the DMG and the updater ZIP. Package `Pulse.app` and an `Applications` link; provide `Pulse-<version>.dmg` and its `.sha256` file using the DMG basename so `shasum -a 256 -c` works in the download directory. Also publish `Pulse-<version>.zip` and `Pulse-<version>.zip.sha256` produced from that same app; the DMG and ZIP must contain the same signed bundle.
- `scripts/release.sh <version>` is the single supported release path. It owns the tests, the `project.yml` version bump and XcodeGen regeneration, the universal Release build and local Apple Development signing, DMG/ZIP packaging with checksums and payload verification, installation of the verified build, then commit/tag/push and GitHub release creation with the four assets. The lower-level commands above are for diagnosis or recovery, not an alternate publication flow.
- Install and verify the signed build at `/Applications/Pulse.app` before committing, tagging, pushing or creating the GitHub release. The locally installed app, the DMG and the ZIP must be the same signed build; the in-app updater consumes that ZIP and its verification chain (identifier, version, team and signature) must accept it. Abort before publication when any script step fails so partial or mismatched assets are never published.
- Release notes live in `docs/releases/<version>.md` and the README release link points at the matching tag. The tag version, asset basenames, embedded bundle version and updater expectations must agree.
- Verify the image, mount it read-only without browsing, and validate app signature, version/build, architectures, executable bytes, resource signature, and Applications link before publication. Eject the image afterward. On hosts reporting legacy `hdiutil` commands deprecated, consult the current `diskutil image` help for future tooling changes; a successful existing image operation remains valid evidence.
- Stage and verify the new local app before stopping the old one. Gracefully quit Pulse, preserve the complete old app in a timestamped backup outside the repository, then replace `/Applications/Pulse.app`. Restore the old app if replacement fails. Launch the explicit installed path and verify one running instance, its executable path, bundle version and release executable hash.
- Installation does not migrate/delete task data, preferences or Keychain items. A normal launched app may refresh existing integrations; synthetic tests must continue using isolated data and the live-usage startup gate.
- Source publication uses the existing repository `https://github.com/zibochen6/Pulse.git` and default `main`, with non-forced fast-forward pushes and a new version tag pointing to the verified release source. Never rewrite an existing published tag or overwrite an unrelated remote update. Only task-owned source/docs are staged; preserve unrelated untracked files.
- Keep release binaries, staging and signing/install manifests outside Git. The versioned release notes and README links must match actual tag/asset names. Use a notes file rather than escaped multiline shell text.
- If direct Git HTTPS fails on a Mac while GitHub API access works, inspect the existing system proxy. Git may need a per-command `http.proxy` option; do not rewrite global proxy configuration or print authentication tokens.
- Verify published main/tag SHA, release visibility/latest state, asset names/sizes/digests, and local checksum. Work commits precede task archival and journal commits; bookkeeping must not alter the tagged app source.

## 4. Validation & Error Matrix

| Condition | Required action |
| --- | --- |
| Source/generated/bundle versions differ | Fix and rebuild before signing/publication |
| Release lacks either architecture | Rebuild with both architectures; do not advertise universal support |
| Signature or mounted payload mismatch | Do not install or publish the artifact |
| Installed Pulse cannot quit gracefully | Leave existing app/data intact; resolve before replacement |
| App replacement fails | Restore the old bundle from its recoverable location |
| Native desktop inspection times out | Report that boundary; bundle/process checks do not certify live menu interaction |
| Remote main advanced | Integrate safely and revalidate; never force-push over it |
| Target tag/release already exists | Inspect state and recover a known partial operation; do not retarget or overwrite blindly |
| Upload outcome is unknown | Read release/asset state before retrying |
| A release-script test/build/sign/package/install step fails | Stop before commit, tag, push and release; fix and rerun; never publish partial assets |
| ZIP or its checksum is missing, or its digest disagrees with the DMG | Do not publish; rebuild both artifacts from the same verified app |
| The published ZIP fails the updater verification chain | Do not tag/push or expose the release as latest; inspect identifier, version, signature and team |

## 5. Good / Base / Bad Cases

- Good: signed universal 0.1.2/build 6 is byte-identical in the DMG and installed app; GitHub publishes the corresponding source tag and SHA-256 file.
- Good: `./scripts/release.sh 0.1.3` publishes signed universal 0.1.3/build 7 as DMG and ZIP with matching checksums from the one verified/installed app, and the in-app updater accepts that ZIP.
- Base: the Mac can development-sign and run locally but has no Developer ID/notarization setup; publish an accurately labelled preview through the existing channel.
- Bad: a new README points at v0.1.2 while the packaged Info.plist still says 0.1.1. Regenerate and rebuild rather than relabelling the old binary.
- Bad: publishing a ZIP or DMG that was built separately from the installed verified bundle, or tagging/pushing before local installation is verified; users then receive assets the updater rejects after the release is public.

## 6. Tests Required

Retain current feature test evidence. Metadata-only changes need version/link/project checks plus the actual universal Release build, not duplicated behavior tests. Verify signing, mounted artifacts and checksums, installed executable equality, and a single process at the installed path. For the four-asset release, verify both published checksums with `shasum -a 256 -c`, confirm the GitHub asset digest agrees, and confirm the updater's verification chain accepts the published ZIP (a local-feed rehearsal is acceptable evidence). Remote acceptance checks the tag/main commit and release asset metadata/digests. Keep live account/UI verification claims separate from synthetic tests and process checks.

## 7. Wrong vs Correct

```sh
# Wrong: changing only generated project metadata; regeneration loses the version.
# Edit Pulse.xcodeproj/project.pbxproj alone.

# Correct: change project.yml first, regenerate, then inspect both configurations.
xcodegen generate
git diff -- project.yml Pulse.xcodeproj/project.pbxproj
```

```sh
# Wrong: publish first and build/install later, or package a separately built ZIP.
git tag v0.1.3 && git push origin v0.1.3
gh release create v0.1.3 Pulse-0.1.3.dmg Pulse-0.1.3.zip

# Correct: one command owns build, verification, local installation and publication.
./scripts/release.sh 0.1.3
```
