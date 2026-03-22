# DragonHealth Agent Rules

Project identity
- Repo: DragonHealth
- Repo root: /Users/renekeller/Projects/Dragonhealth
- Package: DragonHealth
- iOS project: DragonHealthApp/DragonHealthApp.xcodeproj
- Main app target: DragonHealthApp

Rules
- Never edit files outside this repository.
- Never reference DragonGolf or DragonStoic unless explicitly asked.
- Before making code changes, first confirm:
  - current branch
  - whether the working tree is clean
  - top-level repo structure
- Do not rename project structure unless explicitly requested.
- Prefer small, reviewable changes.
- Use feature branches for code changes when asked.
- Never run destructive git commands unless explicitly asked.
- Never change git branches unless explicitly asked.

UX/UI review subagent
- When the task is to review user experience, interface quality, consistency, or visual polish, use a dedicated subagent instead of mixing that work into general implementation.
- Use `/Users/renekeller/Projects/Dragonhealth/Docs/agents/ux-ui-reviewer.md` as the source brief for that subagent.
- Scope the subagent to user-facing flows across the app, not single screens in isolation.
- Default output should be prioritized findings with concrete file references and recommended UX/UI direction.

Picasso design-implementation agent
- When the task is to improve or implement DragonHealth's UX/UI, use the `Picasso` agent instead of ad hoc UI edits.
- Use `/Users/renekeller/Projects/Dragonhealth/Docs/agents/picasso.md` as the source brief.
- Scope Picasso to user-facing implementation work across flows, surfaces, and shared styling.
- Default output should be small, reviewable UI changes that move the app toward a calm, zen-like, highly usable experience.
