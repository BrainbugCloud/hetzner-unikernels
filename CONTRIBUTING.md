# Contributing

## Commits must be signed

Every commit on `main` carries an SSH signature. GitHub displays them as "Verified" on the PR page — that's what reviewers look for before merging.

Signing is already configured globally on the author's machine (`user.signingkey`, `gpg.format=ssh`, `commit.gpgsign=true`). If you clone this repo and `git log --pretty='%G? %s' -1` shows `N` (no signature) on a commit you just made, your repo-local `.git/config` probably has `commit.gpgsign=false` overriding global. Fix with:

```bash
git config --local --unset commit.gpgsign
```

Then amend or redo the commit — signing happens at commit time, not push time.

The SSH signing key used for `@BrainbugCloud` commits here is `~/.ssh/brainbug_hetzner`. The public half is registered under *Settings → SSH and GPG keys → Signing keys* on the author's GitHub account.

## What not to commit

The `.gitignore` already excludes these, but worth calling out:

- **OPS build artifacts** — `*.img`, `.ops/`.
- **Unikraft build output** — `.build-*/`, `.unikraft/`, `image/`, `.config.*` (kconfig drops).
- **Compiled Go binaries** — `examples/*/hello-http`, `examples/*/hello-dd`. The source is in `main.go`; `ops build` produces the binary.

If `git status` ever shows one of these staged, `git rm --cached` it and check your `.gitignore` hasn't been truncated.
