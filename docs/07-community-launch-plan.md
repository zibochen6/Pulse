# Product presentation and community launch

## Positioning

Pulse is a local-first macOS menu-bar companion for people who use AI services
every day: inspect real usage, then take the next small action in a local to-do
list. Pulse 0.1.8 includes Codex quota windows, optional 88VIP/DeepSeek
balances, independent tag lists, daily repeat, task deletion undo, an adaptive
400 × 520 panel and categorized native Settings. Demonstration assets use this
interface and clearly label their synthetic accounts and tasks.

## Demonstration contract

Show the product people will actually use. Export native product views with
isolated sample tasks, deterministic provider responses, in-memory fake secrets
and inactive updates. Every image/video identifies its data as illustrative.
Never use a personal task, real API key or private account balance. The demo must
use the same view components and transitions as the app, rather than a separate
marketing-only interface or artificial animation overlay.

Provide English and Simplified Chinese Home and Settings screenshots in light
and dark appearances. A 15–20 second demonstration should show a coherent daily
flow: see usage, select a list, add a task, complete it, discover tag management,
and open clear service settings. Avoid unexplained jump cuts, exaggerated motion
or a procession of features that cannot be understood at normal playback speed.

Keep values honest: percentage windows and account balances are distinct;
CNY and USD are not summed; a saved key is not proof of connection. A first-use
screenshot should show connection affordances, while an error screenshot should
make its recovery action obvious. Long amounts and many tags must remain usable,
not merely look good in the ideal fixture.

## Before public promotion

- Complete build, storage, lifecycle, localization and native interaction checks.
  Render tests alone do not prove mouse delivery, Chinese IME or animation feel.
- Review README as the trust landing page: actual supported OS/providers,
  local storage, key handling, install instructions and release limitations.
- Keep screenshots tied to the matching release. The current redesign is
  available in 0.1.8; earlier downloads do not contain it.
- The current public preview uses Apple Development signing, not Developer ID
  notarization. A broader launch still needs the existing release-delivery
  signing/notarization and clean-install work. Publishing the preview does not
  authorize contacting testers or posting to external communities.

## Feedback and distribution

After the preview is verified, test with a small group: can someone find tag
rename without being told to right-click, understand each service's state, add a
task without losing focus, and recover from an invalid key? Measure task success
and observed friction rather than assuming more animation increases adoption.

Then share a truthful demo in appropriate Mac/AI communities, disclose creator
affiliation, ask for specific feedback and follow each community's rules.
Publishing and contacting testers are separate, explicit actions. Pulse has no
analytics; this plan does not silently add tracking, claim adoption or fabricate
user feedback.
