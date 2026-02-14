# Changelog

## 2026-02-15
- CHORE: Make changelog creation opt-in

- The `update_changelog` function now checks the `force_create` variable before proceeding.
- This change makes the creation of `CHANGELOG.md` an opt-in feature, requiring explicit user action or configuration to trigger.
- The previous logic would create the file if it didn't exist and `force_create` was true, but the intent is now more explicit.

## 2026-02-14
- FEAT: Add automatic large-commit splitting into multiple commits
- FEAT: Add `split`, `no-split`, and `dry-run` command support
- FEAT: Add script release metadata with `version` command
- FEAT: Add `check-update` and `update` commands using `https://git-auto.hubfly.cloud/git-commit-auto.sh`
- FIX: Support multi-argument command parsing and real changelog updates in `.sh` script
- DOCS: Update README and index site for new command set and release flow

## 2025-11-27
- DOCS: Add changelog update functionality to README
- CHORE: Add changelog update functionality
