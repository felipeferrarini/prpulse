# Changelog

All notable changes to PRPulse. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.8.0] - 2026-10-31

### Added

- **Stacks.** Pull requests in a GitHub stack are put together in one row, with a layers icon, how many there are, and their place (`1/3`) on each of them. Click it and the list becomes that stack, bottom first, with two actions: review the stack as a whole (one conversation that sees all of its pull requests, from the bottom to the top) or review each one. The same goes for your own pull requests. A host without stacks, like GitHub Enterprise Server, shows the plain list.
- **Several pull requests at once.** **Select** above the list of reviews puts a checkbox on each row (a stack ticks all of its own), and **Review together** gives the chosen ones, from any repository, to one conversation, or **Review each** starts one for each. A review of several repositories opens in the first one's folder and can read the clones of the others, but not write to them. The request text has a new `{urls}` placeholder for the list.

## [0.7.0] - 2026-10-30

### Added

- **What's new.** A page in Settings with what changed in each version of PRPulse: the current one open, the earlier ones one click away. It reads the changelog that ships with the app.

### Changed

- The setup wizard has a step for reviews with Claude (turn them on, see whether Claude Desktop and Claude Code are ready, choose who approves), before the mascot.
- While the setup wizard or Settings is open, PRPulse shows in the Dock and the app switcher (⌘Tab), with a menu bar of its own (Quit, the editing commands, Close), so the window can be found again after another app takes the front. It goes back to the menu bar alone when the last window closes.

### Fixed

- Every step of the setup wizard now scrolls when its content is taller than the window (the Exceptions step cut off its last switch), and so does the list of pages in Settings.

## [0.6.0] - 2026-10-30

### Added

- **Review with Claude.** On a pull request waiting for your review, the `⋯` menu and the right click have a new action that opens a session in Claude Desktop with the request already written. If you have a review skill under `~/.claude` (yours or a plugin's), the request names it; otherwise it asks for a review focused on performance, security and code and project conventions. Only the PR's address and number go in the request, never its title or description. It needs Claude Desktop on the Mac, and the session opens in the repository's clone, which PRPulse finds in your usual folders (or asks for) so Claude can read the code.
- **Reviews in the background.** With Claude Code installed and signed in, "Review with Claude" runs the review on its own, without opening anything. A `✦` button in the panel header lists the reviews in progress (what the agent is reading, how long it has been going) and the ones done; opening one shows the review, with buttons to continue it in Claude Desktop or Terminal, copy it or try again. A notification and the mascot tell you when it is ready. The agent reads the code and the PR on its own (`gh pr view`, `gh pr diff`, `git log`…). Settings → Agents → **Approvals** decides the rest. **Automatic**, the default, uses Claude Code's auto mode, and PRPulse keeps the review read-only on top of it: commands run in a sandbox where the repository folder cannot be written and only GitHub can be reached, and editing files, changing git or writing to GitHub is denied. **Ask me** makes anything beyond reading wait with what it wants to do shown, with a notification and the mascot, and Allow or Deny answers it once. A review is stopped after 20 minutes. A note under a finished review says how to ask Claude Desktop to import it into its session list (Help → Troubleshooting → Import Claude Code CLI sessions). The menu keeps "Open draft in Claude Desktop" as the other choice, and the draft is also what you get without Claude Code.
- **Follow-ups.** Under a review that is ready there is a box to ask more in the same conversation, for a while after it finished (and after that PRPulse picks the session up again). Stop interrupts the answer and keeps the review.
- **A default project per organization.** If you keep all of an organization's projects under one root folder and run your sessions there, set that folder in Settings → Agents: every review of the organization opens in it. A folder picked for a single repository wins over it, and when PRPulse asks where a repository is, a checkbox sets the answer for the whole organization.
- **Settings → Agents:** turn the action on or off, see whether Claude Desktop and Claude Code are ready (and what to do when the latter is not signed in), choose who approves (Automatic or Ask me), pick the skill (automatic by default), set the default projects, edit the request text and see or forget the folders chosen for single repositories.

## [0.5.4] - 2026-10-30

### Fixed

- The setup wizard and the Settings window can now be dragged by their top strip, where a title bar would be. They have no title bar, and their content took every click, so they stayed stuck in the middle of the screen.

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
