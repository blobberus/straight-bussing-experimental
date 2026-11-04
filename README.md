# straight-bussing-experimental

Test platform for Straight Bussing changes made from rider feedback. It started as a one-time copy of
[blobberus/straight-bussing](https://github.com/blobberus/straight-bussing) on 2026-10-27 (main at `e3d8aaf`, full
history, every code branch, tag `v1-final`), and was brought up to date with the main project once more on 2026-11-02
at the owner's request (main at `ba4f450`), as the base for the interface redesign (`Straight Bussing New
Version.txt`, `docs/REDESIGN-AUDIT.md`, `docs/DESIGN-SPEC.md`).

**Not synced, in either direction.** Nothing here updates the main project and nothing there updates this copy
(the 2026-11-02 update was a one-time merge the owner asked for). A
change that works here goes to the main project only when it is ported by hand (for example `git format-patch` here,
`git am` in the main clone).

## What is different from the main project

- **Test site (since 2026-11-03, owner):** https://blobberus.github.io/straight-bussing-experimental/ serves the
  redesigned web app (`pages.yml`, Pages source GitHub Actions; it also refreshes the schedule data daily). Visits there
  never count in the live app's usage statistics (`web/js/data/usage.js` skips this path); the feedback form is the
  same as the live app's.
- **GitHub Actions: `ios.yml` and `pages.yml` are enabled** (owner, 2026-11-02 and 2026-11-03): ios.yml builds and
  tests the iPhone app and keeps the simulator screenshots as the run artifact `ios-simulator-preview` (its gallery
  publish step still runs only in the main repo). Disabled: the ground-truth collector, archive and context jobs (the main
  project keeps collecting; a second collector would only duplicate it), `collector-tests.yml`, the Pages deploy, and
  never the App Store release job (`ios-release.yml` uses the same bundle id as the real app).
- **Not copied:** the `data` branch (the main project's live dataset), the release archives, issues, secrets,
  variables and the Pages setting.

## Turning on a test site or iOS builds

1. Done on 2026-11-03: Pages source GitHub Actions, `pages.yml` enabled; the test site is at
   https://blobberus.github.io/straight-bussing-experimental/.
2. `ios.yml` is already enabled; its gallery publish step is limited to the main repo, so with a test site you
   would also lift that condition in `.github/workflows/ios.yml`.

Leave `collect.yml`, `archive.yml`, `context.yml` and `ios-release.yml` disabled.

## Still pointing at the main project

- Links in the web app and iOS app (privacy, support, issues) and the iOS app's daily schedule check (it reads the
  public files on blobberus.github.io/straight-bussing; it sends nothing).
- The data tools default to the main repo (`tools/archive_day.py`, `raw_fetch.py`, `replay_day.py`, `monitor.py`):
  do not run them from this copy, or they read from or write to the main project.

Locally: `cd web; python -m http.server 8000`, then open http://localhost:8000.
