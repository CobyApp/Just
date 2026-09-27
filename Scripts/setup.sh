#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The bundled dictionary and the app icon are generated artefacts, but both are
# committed — CI does not need Python, and a checkout is buildable as-is. This
# script only has to produce the Xcode project.
#
# Build-time secrets come from the environment: TUIST_YOUTUBE_API_KEY,
# TUIST_ADMOB_APP_ID, TUIST_ADMOB_INTERSTITIAL_ID and TUIST_MARKETING_VERSION.
# Locally, mise loads them from `.env`; in CI they are GitHub secrets. Unset,
# the project still generates, with no video search and Google's test ad ids.

# Without mise (a plain Homebrew tuist), nothing else reads `.env`, so it is
# loaded here. Values already in the environment win, which keeps CI's secrets
# in charge there.
if [[ -f .env ]]; then
  while IFS='=' read -r name value; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -z "${!name:-}" ]] && export "$name=$value"
  done < .env
fi

# Fetches the Swift packages (Google Mobile Ads) into Tuist/.build, which is
# not committed. Cheap when they are already there.
tuist install
tuist generate --no-open
