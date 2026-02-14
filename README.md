# Git Commit Auto (Gemini AI)

`git-commit-auto` generates Conventional Commit messages from your staged diff, then commits for you.

It now supports:
- Automatic split into multiple commits for large staged changes
- Self-update from `https://git-auto.hubfly.cloud/git-commit-auto.sh`
- Built-in version + release timestamp reporting

## Dependencies

- `git`
- `curl`
- `jq`
- `GEMINI_API_KEY` environment variable

## Install

1. Get a Gemini API key.
2. Export it in your shell config:

```bash
export GEMINI_API_KEY="YOUR_API_KEY_HERE"
```

3. Install script:

```bash
curl -L https://git-auto.hubfly.cloud/git-commit-auto.sh -o git-commit-auto
chmod +x git-commit-auto
sudo mv git-commit-auto /usr/local/bin/
```

## Commands

```bash
git commit-auto                  # Commit staged changes
git commit-auto push             # Commit then push
git commit-auto regenerate       # Regenerate/amend last commit message
git commit-auto changelog        # Also append commit message(s) to CHANGELOG.md
git commit-auto split            # Force split staged files into multiple commits
git commit-auto no-split         # Disable automatic split for this run
git commit-auto dry-run          # Preview message(s), do not commit
git commit-auto version          # Show version + release datetime
git commit-auto check-update     # Check if update is available
git commit-auto update           # Download and replace current script
git commit-auto help             # Show help
```

You can combine arguments:

```bash
git commit-auto split push changelog
```

## Large Commit Splitting

When staged changes are large, the script automatically creates multiple commits.

Default split trigger:
- More than `8` staged files, or
- More than `500` total changed lines in staged diff

Default chunk size:
- `4` files per commit

Notes:
- Split mode is file-based.
- Split mode blocks partially staged files to avoid accidental staging behavior changes.

## Version and Release Metadata

Each script release includes:
- `SCRIPT_VERSION`
- `SCRIPT_RELEASED_AT` (UTC timestamp)

Check current release:

```bash
git commit-auto version
```

## Self Update

Update in place from the official URL:

```bash
git commit-auto update
```

Check first:

```bash
git commit-auto check-update
```

## Changelog Integration

If you pass `changelog`, generated commit message(s) are appended under today's date in `CHANGELOG.md`.

If `CHANGELOG.md` does not exist, it will be created.

## Safety Note

`regenerate push` uses `git push --force-with-lease` because amend rewrites commit history.
