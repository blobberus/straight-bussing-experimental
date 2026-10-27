# straight-bussing-experimental

Test platform for Straight Bussing changes made from rider feedback. It started as a one-time copy of
[blobberus/straight-bussing](https://github.com/blobberus/straight-bussing) on 2026-10-27 (main at `e3d8aaf`, full
history, every code branch, tag `v1-final`).

**Not synced, in either direction.** Nothing here updates the main project and nothing there updates this copy. A
change that works here goes to the main project only when it is ported by hand (for example `git format-patch` here,
`git am` in the main clone).

## What is different from the main project

- **All GitHub Actions workflows are disabled** (Actions tab): no ground-truth collector, archive or context jobs
  (the main project keeps collecting; a second collector would only duplicate it), no Pages deploy, no iOS builds,
  and never the App Store release job (`ios-release.yml` uses the same bundle id as the real app).
- **Not copied:** the `data` branch (the main project's live dataset), the release archives, issues, secrets,
  variables and the Pages setting.

## Turning on a test site or iOS builds

1. Settings > Pages > Source: **GitHub Actions**; then enable `pages.yml` in the Actions tab and run it. The test site
   is then at https://blobberus.github.io/straight-bussing-experimental/.
2. For iOS builds also enable `ios.yml` (it redeploys Pages with the simulator gallery, so step 1 comes first).

Leave `collect.yml`, `archive.yml`, `context.yml` and `ios-release.yml` disabled.

## Still pointing at the main project

- Links in the web app and iOS app (privacy, support, issues) and the iOS app's daily schedule check (it reads the
  public files on blobberus.github.io/straight-bussing; it sends nothing).
- The data tools default to the main repo (`tools/archive_day.py`, `raw_fetch.py`, `replay_day.py`, `monitor.py`):
  do not run them from this copy, or they read from or write to the main project.

Locally: `cd web; python -m http.server 8000`, then open http://localhost:8000.
