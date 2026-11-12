# Security

## Reporting a problem

Please report a vulnerability **privately**, through [GitHub security advisories](https://github.com/felipeferrarini/prpulse/security/advisories/new), and not in a public issue.
Say what you found, how to reproduce it, and which version you ran. This is a small project, so replies are best effort.

Only the latest release gets fixes.

## What PRPulse handles

- A personal token or an OAuth token is stored in the **macOS Keychain**. With the `gh` option, the token is read from `gh` on demand and never stored by PRPulse.
- PRPulse only reads from GitHub, with one exception: a **nudge**, which you start from a pull request. To get a review (on a pull request of your own) it asks GitHub for a new review from one person and adds a comment; to say a pull request can be merged (on one you reviewed) it only adds a comment. The comment carries a hidden marker (the recipient, an id, a tone, the kind of nudge and an optional message of up to 140 characters). Nothing else is created, edited or deleted. A nudge is honored only when the author of the pull request wrote it to get a review, or a person who reviewed the pull request wrote it to its author to merge; at most three, three hours apart, count for each sender.
- Nothing leaves your Mac except calls to GitHub (and the update check, which reads the appcast from GitHub Releases).
- Review with AI only opens an app or a terminal on your Mac, with the pull request's address in the request. For a terminal it writes a short `.command` script to the temporary folder, with every value quoted, and deletes it after an hour. Anything the agent then does follows the terms and the permissions of that app, which you approve there.
