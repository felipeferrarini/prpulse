import Foundation
import Testing
@testable import PRPulseCore

private let request = ReviewRequest(
    ref: PullRequestRef(owner: "acme", repo: "web", number: 412),
    url: URL(string: "https://github.com/acme/web/pull/412")!
)

// MARK: Prompt

@Test func promptFillsTheRequestPlaceholders() {
    let text = ReviewPrompt.render("Review {repo} #{number}: {url}", for: request)

    #expect(text == "Review acme/web #412: https://github.com/acme/web/pull/412")
}

@Test func promptFillsTheSkillAndLeavesItEmptyWithoutOne() {
    #expect(ReviewPrompt.render("Use {skill}.", for: request, skill: "code-review") == "Use code-review.")
    #expect(ReviewPrompt.render("Use {skill}.", for: request) == "Use .")
}

@Test func promptReplacesInOnePassSoAValueCannotInjectAPlaceholder() {
    let text = ReviewPrompt.render("{skill} {url}", for: request, skill: "{url}")

    #expect(text == "{url} https://github.com/acme/web/pull/412")
}

@Test func promptKeepsUnknownBracesAsTheyAre() {
    #expect(ReviewPrompt.render("{what} {url}", for: request) == "{what} https://github.com/acme/web/pull/412")
}

@Test func templateChoiceFollowsTheCustomTextThenTheSkill() {
    let generic = "generic"
    let withSkill = "with skill"

    #expect(ReviewPrompt.template(custom: "mine", generic: generic, withSkill: withSkill, skill: "x") == "mine")
    #expect(ReviewPrompt.template(custom: "  \n", generic: generic, withSkill: withSkill, skill: "x") == withSkill)
    #expect(ReviewPrompt.template(custom: "", generic: generic, withSkill: withSkill, skill: nil) == generic)
}

// MARK: Link

@Test func linkCarriesThePromptAndTheFolderEncoded() throws {
    let url = try #require(ClaudeDesktopLink.newSession(prompt: "Review a&b=c +d\nnext", folder: URL(fileURLWithPath: "/Users/me/My Code/web")))

    #expect(url.absoluteString == "claude://code/new?q=Review%20a%26b%3Dc%20%2Bd%0Anext&folder=%2FUsers%2Fme%2FMy%20Code%2Fweb")
}

@Test func linkWithoutAFolderHasOnlyThePrompt() throws {
    let url = try #require(ClaudeDesktopLink.newSession(prompt: "Review", folder: nil))

    #expect(url.absoluteString == "claude://code/new?q=Review")
}

@Test func linkRefusesAPromptThatWouldRunAsACommandOrIsEmpty() {
    #expect(ClaudeDesktopLink.newSession(prompt: "/review 12", folder: nil) == nil)
    #expect(ClaudeDesktopLink.newSession(prompt: "  /review", folder: nil) == nil)
    #expect(ClaudeDesktopLink.newSession(prompt: "   \n", folder: nil) == nil)
}

@Test func linkEncodesNonAsciiText() throws {
    let url = try #require(ClaudeDesktopLink.newSession(prompt: "Faça a revisão", folder: nil))

    #expect(url.absoluteString == "claude://code/new?q=Fa%C3%A7a%20a%20revis%C3%A3o")
}

// MARK: Skills

private func makeHome(_ files: [String: String]) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-home-\(UUID().uuidString)")
    for (path, text) in files {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return home
}

@Test func frontmatterGivesTheNameAndTheDescription() {
    let text = """
    ---
    name: code-review
    description: "Review a pull request"
    ---
    # Body
    description: not this one
    """

    let parsed = ReviewSkillCatalog.frontmatter(text)

    #expect(parsed.name == "code-review")
    #expect(parsed.description == "Review a pull request")
}

@Test func frontmatterIsEmptyWithoutTheFence() {
    let parsed = ReviewSkillCatalog.frontmatter("name: nope\n")

    #expect(parsed.name == nil)
    #expect(parsed.description == nil)
}

@Test func discoveryFindsPersonalAndPluginSkillsAboutReviews() throws {
    let home = try makeHome([
        ".claude/skills/review-pr/SKILL.md": "---\nname: review-pr\ndescription: Reviews pull requests\n---\n",
        ".claude/skills/deploy/SKILL.md": "---\nname: deploy\ndescription: Ships to production\n---\n",
        ".claude/plugins/cache/market/tools/1.0.0/skills/code-review/SKILL.md": "---\nname: code-review\ndescription: Code review a pull request\n---\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    let skills = ReviewSkillCatalog.discover(home: home)

    #expect(skills.map(\.name) == ["review-pr", "code-review"])
    #expect(skills.map(\.source) == [.personal, .plugin("tools")])
}

@Test func discoveryFallsBackToTheFolderNameAndMatchesTheDescription() throws {
    let home = try makeHome([
        ".claude/skills/audit/SKILL.md": "---\ndescription: Helps with code review of a branch\n---\n",
        ".claude/skills/checks/SKILL.md": "no frontmatter at all",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    let skills = ReviewSkillCatalog.discover(home: home)

    #expect(skills.map(\.name) == ["audit"])
}

@Test func discoveryRanksNameMatchesFirstThenPersonalOnesAndKeepsOneCopyOfAPluginSkill() throws {
    let home = try makeHome([
        ".claude/skills/helper/SKILL.md": "---\nname: helper\ndescription: Does a review when asked\n---\n",
        ".claude/skills/pr-review/SKILL.md": "---\nname: pr-review\ndescription: x\n---\n",
        ".claude/plugins/cache/m/p/1.0.0/skills/code-review/SKILL.md": "---\nname: code-review\ndescription: x\n---\n",
        ".claude/plugins/cache/m/p/2.0.0/skills/code-review/SKILL.md": "---\nname: code-review\ndescription: x\n---\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    let skills = ReviewSkillCatalog.discover(home: home)

    #expect(skills.map(\.name) == ["pr-review", "code-review", "helper"])
}

@Test func discoveryWithoutAnyClaudeFolderIsEmpty() throws {
    let home = try makeHome([:])
    defer { try? FileManager.default.removeItem(at: home) }

    #expect(ReviewSkillCatalog.discover(home: home).isEmpty)
}

@Test func automaticChoiceTakesTheBestSkillByNameAndNothingForADescriptionOnlyMatch() {
    let byName = ReviewSkill(name: "pr-review", summary: "", source: .personal)
    let byDescription = ReviewSkill(name: "helper", summary: "Does a review", source: .personal)

    #expect(ReviewSkillCatalog.automatic(from: [byName, byDescription]) == byName)
    #expect(ReviewSkillCatalog.automatic(from: [byDescription]) == nil)
    #expect(ReviewSkillCatalog.automatic(from: []) == nil)
}

@Test func skillChoiceResolvesAutomaticNoneAndAName() {
    let skills = [ReviewSkill(name: "pr-review", summary: "", source: .personal), ReviewSkill(name: "other-review", summary: "", source: .personal)]

    #expect(ReviewSkillCatalog.resolve(choice: ReviewSkillCatalog.automaticChoice, from: skills)?.name == "pr-review")
    #expect(ReviewSkillCatalog.resolve(choice: ReviewSkillCatalog.noneChoice, from: skills) == nil)
    #expect(ReviewSkillCatalog.resolve(choice: "other-review", from: skills)?.name == "other-review")
    #expect(ReviewSkillCatalog.resolve(choice: "gone", from: skills) == nil)
}

// MARK: Repository

@Test func locatorFindsACloneByItsRemote() throws {
    let home = try makeHome([
        "Projects/acme/web/.git/config": "[remote \"origin\"]\n\turl = git@github.com:Acme/Web.git\n",
        "Projects/acme/api/.git/config": "[remote \"origin\"]\n\turl = https://github.com/acme/api.git\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    let found = RepositoryLocator.find(owner: "acme", repo: "web", roots: [home.appendingPathComponent("Projects")])

    #expect(found?.lastPathComponent == "web")
}

@Test func locatorMatchesTheWholeNameAndNotAPrefix() throws {
    let home = try makeHome([
        "Projects/web-old/.git/config": "[remote \"origin\"]\n\turl = https://github.com/acme/web-old.git\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    #expect(RepositoryLocator.find(owner: "acme", repo: "web", roots: [home.appendingPathComponent("Projects")]) == nil)
}

@Test func locatorDoesNotLookInsideARepositoryOrBeyondTheDepth() throws {
    let home = try makeHome([
        "Projects/outer/.git/config": "[remote \"origin\"]\n\turl = https://github.com/acme/outer.git\n",
        "Projects/outer/vendor/web/.git/config": "[remote \"origin\"]\n\turl = https://github.com/acme/web.git\n",
        "Projects/a/b/c/d/web/.git/config": "[remote \"origin\"]\n\turl = https://github.com/acme/web.git\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }

    #expect(RepositoryLocator.find(owner: "acme", repo: "web", roots: [home.appendingPathComponent("Projects")]) == nil)
}

@Test func locatorSkipsAMissingRoot() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nowhere-\(UUID().uuidString)")

    #expect(RepositoryLocator.find(owner: "acme", repo: "web", roots: [missing]) == nil)
}

@Test func folderKeyIsTheOwnerAndNameInLowerCase() {
    #expect(PullRequestRef(owner: "Acme", repo: "Web", number: 1).folderKey == "acme/web")
}

// MARK: Folders

private let web = PullRequestRef(owner: "Acme", repo: "Web", number: 1)
private let alwaysFolder: (String) -> Bool = { _ in true }

@Test func theFolderPickedForTheRepositoryWinsOverTheOrganizationsDefault() {
    let choice = ReviewFolders.saved(
        for: web, repositories: ["acme/web": "/code/web"], organizations: ["acme": "/code/acme"], isFolder: alwaysFolder
    )

    #expect(choice == .use(URL(fileURLWithPath: "/code/web")))
}

@Test func theOrganizationsDefaultProjectCoversEveryRepositoryOfIt() {
    let choice = ReviewFolders.saved(for: web, repositories: [:], organizations: ["acme": "/code/acme"], isFolder: alwaysFolder)

    #expect(choice == .use(URL(fileURLWithPath: "/code/acme")))
}

@Test func anEmptyRepositoryPathMeansWithoutAFolderEvenWithADefaultProject() {
    let choice = ReviewFolders.saved(for: web, repositories: ["acme/web": ""], organizations: ["acme": "/code/acme"], isFolder: alwaysFolder)

    #expect(choice == .without)
}

@Test func aPathThatIsNoLongerAFolderIsSkippedInFavourOfTheNextOne() {
    let exists: (String) -> Bool = { $0 == "/code/acme" }

    #expect(ReviewFolders.saved(for: web, repositories: ["acme/web": "/gone"], organizations: ["acme": "/code/acme"], isFolder: exists) == .use(URL(fileURLWithPath: "/code/acme")))
    #expect(ReviewFolders.saved(for: web, repositories: [:], organizations: ["acme": "/gone"], isFolder: exists) == nil)
}

@Test func nothingSavedLeavesTheChoiceOpen() {
    #expect(ReviewFolders.saved(for: web, repositories: [:], organizations: [:], isFolder: alwaysFolder) == nil)
    #expect(ReviewFolders.saved(for: web, repositories: [:], organizations: ["acme": ""], isFolder: alwaysFolder) == nil)
}

@Test func ownerKeyIsTheOwnerInLowerCase() {
    #expect(web.ownerKey == "acme")
}
