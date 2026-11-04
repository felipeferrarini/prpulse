# Security

## Reporting a problem

Please report a vulnerability **privately**, through [GitHub security advisories](https://github.com/felipeferrarini/prpulse/security/advisories/new), and not in a public issue.
Say what you found, how to reproduce it, and which version you ran. This is a small project, so replies are best effort.

Only the latest release gets fixes.

## What PRPulse handles

- A personal token or an OAuth token is stored in the **macOS Keychain**. With the `gh` option, the token is read from `gh` on demand and never stored by PRPulse.
- PRPulse only reads from GitHub, with one exception: a **nudge**, which you start from a pull request of your own. It asks GitHub for a new review from one person and adds a comment, which carries a hidden marker (the recipient, an id, a tone and an optional message of up to 140 characters). Nothing else is created, edited or deleted. A nudge is honored only when the author of the pull request wrote it, and at most three, three hours apart, count.
- Nothing leaves your Mac except calls to GitHub (and the update check, which reads the appcast from GitHub Releases).
- Reviews with Claude run the `claude` CLI on your Mac, with a sandbox and a list of tools it may not use. See the README for the details.
