#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The bundled dictionary and the app icon are generated artefacts, but both are
# committed — CI does not need Python, and a checkout is buildable as-is. This
# script only has to produce the Xcode project.
tuist generate --no-open
