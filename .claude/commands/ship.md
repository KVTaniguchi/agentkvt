Run the full commit → PR → merge → deploy loop for changes on the current branch.

Steps:

1. **Run iOS tests** — use the xcodebuild command from the ios-test skill. Stop and report if any tests fail; do not proceed.

2. **Commit all staged/unstaged changes**:
   - `git add` only the modified source files (no .env, no lock files unless explicitly changed)
   - Write a concise commit message: imperative title, blank line, brief body explaining the why
   - Append `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`

3. **Push the branch** to origin.

4. **Create a PR** with `gh pr create`:
   - Title: short imperative phrase (≤70 chars)
   - Body: Summary bullets + Test plan checklist
   - Use `--merge` (preserve commits, no squash) when merging

5. **Merge the PR** with `gh pr merge <number> --merge --delete-branch --repo KVTaniguchi/agentkvt`
   - If merge fails due to worktree conflict, always use `--repo KVTaniguchi/agentkvt` flag

6. **Deploy** — run the deploy command:
   ```
   ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net "cd ~/AgentKVTMac && bash ./bin/deploy_agentkvt_backend.sh origin/main"
   ```
   Watch for migration errors or /healthz failures. Confirm `"ready":true` in the healthz response.

7. **Report**: PR URL, merge SHA, and healthz status.

If any step fails, stop and report the exact error with suggested next steps. Do not skip the test step.
