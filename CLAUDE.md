# FB2 Editor

Flutter app published on Google Play as `com.caragulak.fb2editor`.

## Releasing to Google Play

Before any release, signing or version-bump task, read `docs/RELEASE.md`. It links to the full
instructions, which are kept outside the repo.

- Never commit `android/key.properties`, `*.jks` files, passwords or key fingerprints.
- Ask the user for the keystore passwords; never write them into tracked files.

## Play Console and browser work

Use the Nimvarya MCP (`mcp__nimvarya__*`) for every Play Console step (upload, release notes, store
listing, review replies, checking version codes). Do not use other browser tools for it.
