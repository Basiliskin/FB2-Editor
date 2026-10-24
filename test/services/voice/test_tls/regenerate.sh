#!/usr/bin/env bash
# Writes the self-signed certificate the model download tests trust.
# macOS refuses TLS server certificates valid for more than 825 days, or
# without CA:FALSE and serverAuth, even when the test trusts them directly.
set -euo pipefail
cd "$(dirname "$0")"
openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -subj "/CN=localhost" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "extendedKeyUsage=serverAuth" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -keyout server_key.pem -out server_cert.pem
