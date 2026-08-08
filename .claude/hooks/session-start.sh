#!/bin/bash
# Provisions a Claude Code on the web container so `bin/rails test` and
# `bin/rubocop` work. Mirrors what the Dockerfile and CI already install.
set -euo pipefail

# Local machines are assumed to be already set up; only provision remote ones.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# libvips backs Active Storage variants (the image_processing gem). Without it
# every photo-variant job errors out, so the suite reports phantom failures.
if ! ldconfig -p | grep -q libvips; then
  # Third-party PPAs in the base image are blocked by the network policy and
  # make `apt-get update` exit non-zero; the Ubuntu archives we need still
  # refresh, so don't let that warning abort the hook.
  $SUDO apt-get update -qq || true
  $SUDO apt-get install --no-install-recommends -y libvips42
fi

bundle install --quiet
