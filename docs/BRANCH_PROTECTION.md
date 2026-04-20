# Branch protection — required manual setup

CODEOWNERS and CI workflows do **not** enforce anything on their own.
Without branch protection configured in the GitHub UI, anyone with push
access can still land an unreviewed change to `main` — including a new
`approvals/current.json` signed by an attacker-controlled key.

Flip the following toggles manually, at
`Settings → Branches → Branch protection rules → Add rule` for `main`:

## Required toggles

- [ ] **Require a pull request before merging.**
  Prevents direct pushes to `main` (closes the Path B-style bypass
  where signed approvals are pushed without review).
- [ ] **Require approvals: 1** (minimum).
  Combined with the `.github/CODEOWNERS` file, this requires
  `@Tsukieomie` to approve any change to `approvals/`,
  `.github/workflows/`, or `keys/`.
- [ ] **Require review from Code Owners.**
  This is the toggle that actually activates CODEOWNERS.
- [ ] **Dismiss stale pull request approvals when new commits are pushed.**
  Prevents approve-then-push-more.
- [ ] **Require status checks to pass before merging.**
  - [ ] Add `verify-approval` (the job in
        `.github/workflows/verify-approval.yml`) as a **required**
        check.
  - [ ] Require branches to be up to date before merging.
- [ ] **Require signed commits.**
  Path B (off-runner signing) currently pushes unsigned commits.
  Enabling this closes the "anyone with a stolen token can push a
  pubkey rotation" vector.
- [ ] **Require linear history** (optional, but recommended for audit).
- [ ] **Do not allow bypassing the above settings.**
  In particular, **uncheck** "Allow administrators to bypass" for this
  rule — the whole point is to protect against compromised admin
  credentials as well.
- [ ] **Restrict who can push to matching branches.**
  Remove any service account / deploy key that is not strictly required.
- [ ] **Allow force pushes: disabled.**
- [ ] **Allow deletions: disabled.**

## Interaction with the signing workflow

The `approve-pocket-lab-unlock-signed` workflow pushes to `main` via
`GITHUB_TOKEN` with `contents: write`. When "Require a pull request
before merging" is enabled, direct pushes from the workflow will be
rejected. Two options:

1. **Recommended:** change the workflow to open a PR instead of
   pushing directly, and rely on the `verify-approval` check plus
   manual merge. Slower but auditable.
2. **If direct push is required:** add `github-actions[bot]` (or the
   workflow's identity) to the "Restrict who can push" allowlist.
   Keep the `verify-approval` check in place so the artifact is still
   validated before the push is accepted.

## GitHub Actions: repo-level enablement

If GitHub Actions is **disabled** on this repository (`Settings →
Actions → General`), no workflow here runs — including
`verify-approval`. Before treating these checks as defensive, confirm:

- Actions is set to *Allow all actions and reusable workflows* (or at
  least *Allow select actions* with `actions/checkout` permitted).
- The account has Actions minutes available (private repos on the free
  tier have a monthly cap; if exhausted, new runs will queue or fail
  at startup).

Until Actions is confirmed running on this repo, treat the device-side
verifier as the only live defense.
