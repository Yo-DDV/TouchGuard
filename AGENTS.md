# TouchGuard

- Use English in public code, issues, pull requests and documentation.
- Target `main`; link every change to an issue and merge only after native checks pass.
- Build the independently written code in `modern/`; never execute inherited binaries.
- Run `bash scripts/test.sh <fresh-test-directory>` and `bash scripts/build.sh <fresh-output-directory>`.
- Preserve the event-driven design: no character extraction, raw input logs, runtime dependencies or active polling.
- Check input pairing, fail-open behavior, permission denial, sleep/wake recovery and signing before a release.
- Publish no personal paths, credentials, machine identifiers or local diagnostic captures.
