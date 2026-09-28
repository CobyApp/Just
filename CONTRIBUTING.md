# Contributing & release flow

The `main` branch is always green and always releasable. Everything reaches it
through a pull request that passed CI; releases go out by tagging.

## Branching

Trunk-based, with short-lived branches:

- Branch off `main`: `feat/…`, `fix/…`, `chore/…`.
- Open a PR into `main`. The **Test** check runs on every PR and must pass.
- Merge when it is green. Squash-merge keeps `main`'s history one commit per
  change. Delete the branch after merging.

Direct pushes to `main` are blocked — even a one-line fix goes through a PR, so
nothing lands unbuilt or untested. (The repo admin can lift the rule
temporarily in Settings → Branches if a hotfix truly cannot wait.)

## CI

`.github/workflows/test.yml` runs the unit suite on macOS with the pinned Xcode,
on every PR and every push to `main`. It is the required status check.

Run the same suite locally before opening a PR:

```bash
bundle exec fastlane test
```

## Releasing to TestFlight

Two ways, both of which run the tests first and refuse to build if a release
secret (App Store key, YouTube key, real AdMob ids) is missing:

1. **One click** — Actions → **Release** → run. Pick `patch` / `minor` /
   `major` (or type an exact version). It bumps from the latest tag, pushes the
   `vX.Y.Z` tag, writes the GitHub Release notes, and deploys.

2. **By tag** — push a version tag yourself:

   ```bash
   git tag -a v1.2.0 -m v1.2.0 && git push origin v1.2.0
   ```

   The **Deploy to TestFlight** workflow picks it up, and the tag name becomes
   the marketing version. The build number is the latest TestFlight build + 1.

`workflow_dispatch` on the deploy workflow is also available for a manual run
without a tag (Actions → Deploy to TestFlight → run).

### Required repository secrets

Set under Settings → Secrets and variables → Actions:

| Secret | What it is |
|---|---|
| `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY` | App Store Connect API key (`.p8` contents) |
| `YOUTUBE_API_KEY` | YouTube Data API key |

## Versioning

`vMAJOR.MINOR.PATCH`. The tag is the source of truth for the marketing version;
the manifest default is only a fallback for local builds.
