# App Versioning Concept

## Purpose
This document defines a simple, durable, and automation-friendly versioning system for the Dragonhealth app. The goal is to make versions easy to understand for humans, reliable for tooling, and consistent across platforms and releases.

## Version Fields
We track two version values:

1. Marketing Version (SemVer)
   - Format: MAJOR.MINOR.PATCH (e.g., 2.4.1)
   - Human-facing: appears in app stores, release notes, and documentation

2. Build Number (Monotonic Integer)
   - Format: integer (e.g., 237)
   - Machine-facing: increments for every build/release
   - Never resets or decreases

Together they uniquely identify a release. Example: marketing version 2.4.1 with build number 237.

## SemVer Rules
- MAJOR: breaking changes or major redesigns
  - API or data model changes that are not backwards compatible
  - Significant UX overhauls that change user workflows

- MINOR: new functionality that is backwards compatible
  - New features, screens, or integrations
  - Enhancements that do not break existing behavior

- PATCH: backwards-compatible bug fixes or minor improvements
  - Fixes, small performance improvements, and safe refinements

## Build Number Rules
- Increment for every release build (including hotfix builds)
- Never reuse or decrement
- Serves as the primary ordering key for CI/CD and app stores

## Source of Truth
The version is stored in a single file in the repo:

Docs/version.json

Example:
```
{
  "marketing_version": "2.4.1",
  "build_number": 237
}
```

This file is the authoritative source and should be used to update platform-specific version files during build or release.

## Git Tagging
- Tag each release using the marketing version
  - Example: v2.4.1
- Optionally include build number in annotated tag message
  - Example message: "Build 237"

## Release Workflow
1. Determine change scope (major, minor, patch)
2. Update marketing_version and build_number in Docs/version.json
3. Update CHANGELOG.md with release notes
4. Tag the release in git
5. CI validates:
   - marketing_version increases when release label ("release") is applied
   - build_number increased

## CI Validation Rules (Suggested)
- If a PR has the "release" label:
  - Docs/version.json must be updated in the PR
  - marketing_version must be greater than the previous marketing_version
  - build_number must be greater than previous build_number
- If Docs/version.json is updated without a release label:
  - build_number must be greater than previous build_number
  - marketing_version must not decrease
- CI fails if any rule is violated

## Changelog Policy
- Keep a CHANGELOG.md with release notes aligned to marketing_version
- Each entry includes:
  - Date of release
  - Summary of changes
  - Notable fixes or migrations

## Examples
- New feature release:
  - 2.4.1 -> 2.5.0, build 237 -> 238
- Bugfix release:
  - 2.5.0 -> 2.5.1, build 238 -> 239
- Breaking change:
  - 2.5.1 -> 3.0.0, build 239 -> 240

## Notes
- The marketing version communicates scope and compatibility.
- The build number ensures strict ordering for tooling and app stores.
- Keeping a single source of truth avoids drift across platforms.
