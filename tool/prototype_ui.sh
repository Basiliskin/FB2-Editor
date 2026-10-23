#!/usr/bin/env bash
# PROTOTYPE - THROWAWAY. One command: serves the app in Chrome with the variant switcher.
# Open http://localhost:5151/?variant=A  (keys: 0, A, B, C)  - arrows ←/→ also cycle.
cd "$(dirname "$0")/.." && exec flutter run -d chrome -t lib/prototype/main_prototype.dart --web-port 5151 --web-browser-flag="--window-size=1280,860"
