import PRPulseCore
import SwiftUI

enum SetupStep: Int, CaseIterable {
    case welcome, connect, organization, exceptions, general, agents, mascot, done
}

struct WizardView: View {
    @ObservedObject var model: SetupModel
    let onFinish: () async -> String?
    let onClose: () -> Void
    let onCancel: () -> Void
    let agentAvailability: () -> AgentAvailability
    let cliStatus: () async -> CLIState
    let onTestReviewAgent: () -> Void

    @LocalState private var step: SetupStep
    @LocalState private var slide: Int
    @LocalState private var movingForward = true
    @LocalState private var isBusy = false
    @LocalState private var failure: String?

    static let slideCount = 3
    static let size = CGSize(width: 900, height: 590)
    private static let stageWidth: CGFloat = 378

    init(
        model: SetupModel,
        initialStep: SetupStep = .welcome,
        initialSlide: Int = 0,
        initialFailure: String? = nil,
        onFinish: @escaping () async -> String?,
        onClose: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        agentAvailability: @escaping () -> AgentAvailability = { .ready },
        cliStatus: @escaping () async -> CLIState = { .unknown },
        onTestReviewAgent: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onFinish = onFinish
        self.onClose = onClose
        self.onCancel = onCancel
        self.agentAvailability = agentAvailability
        self.cliStatus = cliStatus
        self.onTestReviewAgent = onTestReviewAgent
        _step = LocalState(initialValue: initialStep)
        _slide = LocalState(initialValue: initialSlide)
        _failure = LocalState(initialValue: initialFailure)
    }

    var body: some View {
        HStack(spacing: 0) {
            WizardStage(model: model, step: step, slide: slide).frame(width: Self.stageWidth)
            main
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .borderlessWindowChrome()
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                WizardProgress(current: step.rawValue, count: SetupStep.allCases.count)
                WindowCloseButton(action: onCancel)
            }
            .padding(.leading, 32)
            .padding(.trailing, 18)
            .padding(.top, 18)
            ZStack {
                content.id(step.rawValue * 10 + slide).transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            if let failure, step == .mascot { failureNote(failure) }
            footer
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeBody(slide: slide) { go(to: .connect) }
        case .connect: ConnectBody(model: model)
        case .organization: OrganizationBody(model: model)
        case .exceptions: ExceptionsBody(model: model)
        case .general: GeneralBody(model: model)
        case .agents: AgentsBody(model: model, availability: agentAvailability, cliStatus: cliStatus, onTest: onTestReviewAgent)
        case .mascot: MascotBody(model: model)
        case .done: DoneBody(model: model)
        }
    }

    private var transition: AnyTransition {
        let edge: Edge = movingForward ? .trailing : .leading
        let opposite: Edge = movingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        )
    }

    private func failureNote(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5))
            .foregroundStyle(WizardPalette.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .transition(.opacity)
            .accessibilityAddTraits(.isStaticText)
    }

    private var footer: some View {
        HStack {
            Button(tr("setup.back")) { goBack() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WizardPalette.ink2)
                .disabled(isBusy)
                .opacity(canGoBack ? 1 : 0)
                .allowsHitTesting(canGoBack)
            Spacer()
            if isBusy { ProgressView().controlSize(.small).padding(.trailing, 8) }
            Button(primaryTitle) { Task { await advance() } }
                .buttonStyle(WizardPrimaryButtonStyle())
                .keyboardShortcut(step == .exceptions ? nil : .defaultAction)
                .disabled(isBusy || (step == .organization && model.draft.orgs.isEmpty))
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var canGoBack: Bool {
        step != .done && !(step == .welcome && slide == 0)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: slide < Self.slideCount - 1 ? tr("setup.continue") : tr("wizard.start")
        case .connect: isBusy ? tr("setup.checking") : tr("wizard.connect.action")
        case .mascot: tr("setup.finish")
        case .done: tr("wizard.done.open")
        default: tr("setup.continue")
        }
    }

    private func advance() async {
        switch step {
        case .welcome:
            if slide < Self.slideCount - 1 { goSlide(slide + 1) } else { go(to: .connect) }
        case .connect:
            isBusy = true
            let valid = await model.validateConnection()
            isBusy = false
            if valid { go(to: .organization) }
        case .organization: go(to: .exceptions)
        case .exceptions: go(to: .general)
        case .general: go(to: .agents)
        case .agents: go(to: .mascot)
        case .mascot:
            isBusy = true
            withAnimation(.easeOut(duration: 0.2)) { failure = nil }
            if let message = await onFinish() {
                withAnimation(.easeOut(duration: 0.2)) { failure = message }
            } else {
                go(to: .done)
            }
            isBusy = false
        case .done: onClose()
        }
    }

    private func goBack() {
        if step == .welcome, slide > 0 { return goSlide(slide - 1) }
        guard let previous = SetupStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    private func goSlide(_ next: Int) {
        movingForward = next > slide
        withAnimation(.spring(duration: 0.45)) { slide = next }
    }

    private func go(to next: SetupStep) {
        movingForward = next.rawValue > step.rawValue
        withAnimation(.spring(duration: 0.45)) {
            step = next
            if next == .welcome { slide = 0 }
        }
    }
}

private struct WizardProgress: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(WizardPalette.card2)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(WizardPalette.accent)
                            .scaleEffect(x: index <= current ? 1 : 0, anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
        }
        .animation(.spring(duration: 0.6), value: current)
        .accessibilityElement()
        .accessibilityLabel("\(current + 1) / \(count)")
    }
}
