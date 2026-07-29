# AGENTS.md

## Project Mission

We are a pair programming team modernizing `ealeksandrov/SomaFM-miniplayer` so it can run well on Apple silicon Macs. Our work is tracked in `matthewbohl/SomaFM-miniplayer-apple-silicon`.

The goal is to preserve the spirit of the original SomaFM mini player while updating the build, runtime, dependencies, packaging, and tests needed for current macOS hardware and tooling. Release builds must remain universal binaries for Apple silicon and Intel Macs, support macOS 13 or later, and remain suitable for Mac App Store distribution.

## Working Principles

- Start from evidence. Check the repository state and read local project context before proposing or editing.
- Keep changes small, reviewable, and reversible.
- Prefer the original app's structure and behavior unless modernization requires a change.
- Document decisions where future contributors will look first.
- Treat Apple silicon support as a compatibility project, not a rewrite by default.
- Keep user-facing behavior steady unless the request explicitly changes it.
- State you assumptions explicitly. Any areas where clarity is needed ask me how we want to handle it. For each question provide a recommendation.
- Protect the user's work. Do not overwrite, revert, or discard changes made outside the current task.
- Keep private developer and machine details out of git. Before every commit, automatically replace accidental team IDs, signing identities, provisioning profile names, local bundle IDs, account names, machine paths, tokens, and credentials with project variables or documented placeholders. Preserve explicitly approved public attribution and contact details.
- Verify with tests, builds, or the closest practical local check before calling work done.
- Keep no more than five committed-but-unpushed changes outstanding.

## Project Context

- Upstream repository: `https://github.com/ealeksandrov/SomaFM-miniplayer`
- Working repository: `https://github.com/matthewbohl/SomaFM-miniplayer-apple-silicon`
- Local branch at project start: `main`
- Local status at project start: fresh repository with no committed files
- Primary platform target: Apple silicon and Intel Macs running macOS 13 or later
- Distribution target: a universal Mac App Store application
- Canonical project documentation: `README.md`

Until source code is imported, all technical assumptions about language, build system, dependencies, and supported macOS versions must be confirmed from local files or from the upstream repository.

## Development Loop

Every implementation task follows this loop:

1. Check current repository status with `git status --short --branch`.
2. Load local project context:
   - read `AGENTS.md`
   - read `README.md`
   - inspect relevant source, build, test, and configuration files
   - check remotes, branches, and recent commits when git history matters
3. Review the request and restate the intended outcome.
4. Propose a primary solution.
5. Propose one alternative solution with tradeoffs.
6. Wait for proposal acceptance before implementing, unless the user explicitly asks to proceed immediately.
7. Implement the accepted solution in focused commits.
8. Update documentation, including `README.md` when project details or command line options change.
9. Generate or update test cases for changed behavior where practical.
10. Run relevant verification commands.
11. Run `Scripts/check-public-repo-safety.sh`, then audit the staged diff for private developer or machine details. Restore project placeholders before committing, without reverting unrelated user changes.
12. Commit completed work.
13. Push committed work before more than five local commits are outstanding.
14. Report what changed, how it was verified, and what remains.

## Documentation Rules

- `README.md` is the canonical project handbook and GitHub-facing README.
- Keep command line options, build commands, test commands, and known setup requirements current.
- Record important modernization decisions near the code or in project docs.
- Do not let documentation drift behind behavior.

## Testing Rules

- Add or update tests when behavior changes.
- Prefer focused tests that protect the modernization work being done.
- When automated tests are not yet available, document the manual verification performed and the gap that remains.
- Build failures on Apple silicon related to architecture, signing, packaging, or dependency compatibility should get regression coverage when possible.

## Git And Release Hygiene

- Keep commits focused and descriptive.
- Do not leave more than five committed changes unpushed.
- Push to `https://github.com/matthewbohl/SomaFM-miniplayer-apple-silicon` once remote access is configured.
- Do not rewrite shared history unless explicitly requested.
- Do not use destructive git commands without explicit approval.
- Never commit `Config/Signing.local.xcconfig` or values copied from it. Confirm staged signing settings still use the `SOMAFM_*` variables from `Config/Signing.xcconfig`.
- Treat a failure from `Scripts/check-public-repo-safety.sh` as a commit blocker. Update the check when a new class of private local data is discovered.

## Agent Notes

- Use `rg` or `rg --files` first when searching.
- Use `apply_patch` for manual edits.
- Before editing, explain the intended edit briefly.
- If the local repo is missing expected upstream files, say so plainly and either import them as an accepted step or ask for direction.
