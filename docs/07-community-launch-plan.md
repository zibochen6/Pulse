# Portfolio and community launch plan

## Positioning

Pulse aims to be a calm macOS menu bar entry point for people who work across AI services. The distinctive promise is **honest usage visibility plus a fast, local to-do list**, with local control. The current repository is only a buildable shell and design research; it is not yet the product described here.

## Proof before promotion

1. Finish the public MVP gate in [the roadmap](06-mvp-roadmap.md). Capture a reproducible demo with a real Codex rate window, at least one verified API balance/spend metric, and ordinary task viewing/adding/completing/tagging. Use demo accounts and synthetic notes, never personal task text or keys.
2. Prepare a short GIF (open menu, refresh, complete a task), two screenshots (normal status and understandable error/permission state), an architecture diagram, and a 60–90 second walkthrough. Show freshness and provider capability labels so visuals do not suggest unsupported data.
3. Make README the trust landing page: exact supported macOS versions and providers, key scopes, local file access, whether anything leaves the machine, limitations, build/run steps, and privacy policy. Keep a concise Chinese summary while providing English issue templates and main documentation for broad reach.
4. Development-signed previews may be downloaded with explicit trust limits,
   release checksums and a versioned changelog. Before broader launch, complete
   Developer ID signing/notarization and clean install testing. Test onboarding
   on a machine with no configured Codex account and provide a direct feedback
   path.

## Community rollout after a working MVP

Start with a small private tester group, fix onboarding and data-safety issues, then post a truthful demo to relevant macOS and AI developer communities where self-promotion is allowed. Tailor each post to that community's problem and rules; disclose creator affiliation, ask for specific feedback, and avoid mass-posting the same copy. Publish a technical build note about local-first task storage and provider capability differences. GitHub stars are a secondary signal; track whether users can connect a service, trust the local task workflow, and return after a week.

## Open-source maintenance

After the first integration milestone, add issue templates for bugs/provider requests, a contribution guide, a capability matrix, and a small set of newcomer tasks. Triage provider breakages separately from product requests, link fixes to source/API evidence, and keep reference-project MIT attribution if any source is later reused. Do not claim users, traction, a release, or support for a provider until it has been shipped and verified.
