#!/bin/sh

set -eu

surge_domain="${1:-${SURGE_DOMAIN:-}}"

if [ -z "$surge_domain" ]; then
  echo "Usage: $0 <surge-domain>" >&2
  echo "Or set SURGE_DOMAIN before running the script." >&2
  exit 64
fi

flutter build web --release
surge build/web "$surge_domain"