# Changelog

All notable changes to PRPulse. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-10-29

### Added

- Self update with [Sparkle](https://sparkle-project.org): the app checks for new versions and installs them in the background. Turn it off in Settings, or use "Check for Updates…" in the right click menu or in Settings. Updates are verified with an EdDSA signature, so they don't need an Apple Developer ID.
- `make appcast` signs the DMG and writes the update feed that is attached to each release.

## [0.2.0] - 2026-10-29

### Added

- A redesigned popover: action filters (review, changes, reply, CI, conflict, merge), a waiting time on every row that turns amber after a day and red after three, and a toggle between a single view and a side by side one, remembered between launches.
- A new menu bar icon: a drawn pull request glyph that becomes one orange pill with the count when something needs you, rings out for a new item and turns red on error.
- A right click menu on the icon: refresh now, open the organization's PRs on GitHub, a notifications switch, settings, about and quit.
- A new setup wizard with a live preview of the popover, a final "all set" step, and organizations ordered by how much you worked in them over the last 90 days.
- Repositories to ignore are listed from the organization instead of typed by hand.
- A new settings window with a sidebar. It counts unsaved changes, marks the section they are in, and lets you discard them or save with Cmd+S.
- Requests to you now come first in the review list.
- `make screenshots` renders the README pictures with fake data.

### Changed

- The wizard and the settings window have no system title bar: rounded corners, their own close button, Esc to close.
- The popover is its own panel anchored under the icon, so changing its layout no longer makes it jump.

## [0.1.0] - 2026-10-29

First release: the My PRs and To review lists in the menu bar, an icon that changes with the state, notifications that fire once per item, a setup wizard, English and Portuguese, a Homebrew cask.
