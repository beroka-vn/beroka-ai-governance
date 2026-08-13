# macOS CI portability design

## Outcome

Make PR #66's existing shell test suite complete on both `ubuntu-latest` and
`macos-latest`, fail promptly instead of hanging, and satisfy the unresolved
Codex review about GNU-only test dependencies.

## Scope

- Replace the current `pty.spawn()` test helper with the smallest portable PTY
  driver that forwards piped input, sends terminal EOF after the pipe closes,
  waits for the child, and returns its exit status.
- Keep one shared helper implementation and source it from the four test files
  that need interactive terminal simulation.
- Replace GNU-only `stat -c` and `sha256sum` assumptions with portable behavior
  using commands already available on Linux and macOS.
- Add a job timeout to the GitHub Actions matrix so a future interactive-test
  regression cannot consume the default six-hour limit.

## Invariants

- Interactive tests continue to exercise a real pseudo-terminal rather than
  bypassing TTY checks.
- Product behavior, bootstrap prompts, release verification, and governance
  routing remain unchanged.
- The repository gains no package installation step or dependency.
- Existing shell tests remain the source of verification; no throwaway test
  harness is added.

## Error handling

The PTY helper must propagate the child process status and terminate cleanly on
stdin EOF. The CI job timeout is a final containment boundary, not a substitute
for fixing the PTY lifecycle.

## Verification

1. Demonstrate the current PTY regression with the existing first interactive
   bootstrap test.
2. Run each affected existing shell test after the fix, then run the complete
   `tests/*.sh` loop locally.
3. Push the reviewed implementation to PR #66 and require both Ubuntu and macOS
   matrix jobs to complete successfully.
4. Re-read the Codex review thread and verify every portability item is covered.

## Alternatives rejected

- Installing GNU Coreutils on the macOS runner hides portability defects in a
  repository intended to support native macOS clients.
- Removing the macOS matrix avoids the requested validation rather than fixing
  it.
- Keeping four copied PTY implementations repeats the same concurrency bug and
  makes future fixes easy to miss.
