- [x] Reproduce it yourself on the matching surface via the driver skill.
- [x] Binary-search the cause.
  Observed absent tunnel/MCP, successful restart, then persistent teardown after child termination.
- [x] Plan the fix.
  Keep task ownership across attempts, retry unexpected exit with capped backoff, cancel intentional disconnect. Luna owns final implementation verification.
- [x] Verify on the same surface.
  Installed app, killed tunnel child, observed new healthy child without app restart in 34.9 seconds; original connector read succeeded. Related tests 28/28 passed.
- [x] Stage the commits so the failing repro lands before the fix in git history.
  skip: No commit or push requested; preserve the shared dirty workspace.
- [x] Run Opening a PR.
  skip: Local repair requested; no PR publication requested.
