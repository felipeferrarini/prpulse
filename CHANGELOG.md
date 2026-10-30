# Changelog

All notable changes to PRPulse. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.5.3] - 2026-10-30

### Fixed

- When finishing the wizard fails (no connection, no access to the organization, SSO not authorized, rate limit), the last step now says why. Before, the message was only shown in the connection step, so *Finish* looked like it did nothing.

## [0.5.2] - 2026-10-30

### Fixed

- The mascot step of the wizard now scrolls when there are more mascots than fit in the window (for example with many of your own packs). The title and the *Show on screen* switch stay in place.

## [0.5.1] - 2026-10-30

### Added

- Two separate switches for bots, in the Exceptions step of the wizard and in Settings, both working on the same list of bot accounts (the ones GitHub marks as bots, plus yours): *Ignore comments from bots* (on, as before) and *Ignore pull requests opened by bots*, which keeps Dependabot, Renovate and the like out of the review list even when they ask for your review. Both are on by default, also after updating: turn the second one off in Settings → Exceptions to see those PRs again.

## [0.5.0] - 2026-10-30

### Added

- A mascot that lives in the bottom right corner of the screen, reacts to the state of your pull requests (calm, asleep, alert with a count, jumping for joy with a speech bubble when something new arrives, worried about PRs that wait for 3 days or more, thinking while it refreshes, sad when GitHub is out of reach) and can be dragged anywhere. Click it to open the panel, right click it for its menu.
- Six characters: Brasa, Byte, Gota, Broto, Nimbo and Seixo. Your own go in `~/Library/Application Support/PRPulse/Mascots/` as a `sprites.png` sheet and a `mascot.json`.
- A last step in the setup wizard to pick the mascot, a Mascot page in Settings (character, size, position, your own characters) and a Show mascot item in the menu bar icon's menu.
- `make mascots` redraws the built-in mascots.

### Notes

- The mascot is on by default and says hello once after the update. Turn it off in Settings or from the menu bar icon.

## [0.4.2] - 2026-10-29

### Changed

- One icon everywhere: the app icon, the big and the small icons in the setup wizard and the logo in the popover header now use the same pull request glyph, orange and ink as the menu bar pill. The wizard shows the pill itself, with its count.

### Fixed

- The rings around the icon in the setup wizard came in from the top left corner instead of leaving the icon. Now a single ring leaves the icon, spreads and fades, slowly, and the animation stops while it is hidden.

## [0.4.1] - 2026-10-29

### Changed

- Much less memory: the panel's content is built when it opens and dropped when it closes, and the lists only build the rows you can see. With 90 pull requests the app went from 85 MB to 42 MB open and 20 MB idle in our measurements.
- `PRPULSE_DEMO=many` shows 90 fake pull requests, to try long lists.

## [0.4.0] - 2026-10-29

### Added

- More than one organization: pick several in the wizard or in Settings. PRs from all of them share the lists, and each row shows `owner/repo` when more than one is watched.
- A **Waiting for review** section under My PRs: your own PRs that went a number of days (2 by default, 1 to 7 or off in Settings) without a review. It never counts in the icon or in notifications, and each row has a Copy link button.
- A **⋯** menu on every row: open on GitHub, copy the link, and mute the repository (review rows only).
- A global shortcut, ⌥⌘P, to open and close the panel. It can be turned off in Settings.
- A **Diagnostics** page in Settings: version, last sync, GitHub request budget and a button that copies a report for bug reports. The report has no token, organization or PR names.
- The update window shows the version's changelog section as release notes.

### Changed

- Repositories to ignore are stored as `owner/name`. Settings saved by earlier versions are converted on the first launch.
- The settings window is taller to fit the new options.

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
