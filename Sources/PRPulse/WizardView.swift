import PRPulseCore
import SwiftUI

enum SetupStep: Int, CaseIterable {
    case welcome, connect, organization, exceptions, general
}

struct WizardView: View {
    @ObservedObject var model: SetupModel
    let onFinish: () async -> String?

    @LocalState private var step: SetupStep
    @LocalState private var slide = 0
    @LocalState private var movingForward = true
    @LocalState private var isBusy = false

    private static let slideCount = 3

    init(model: SetupModel, initialStep: SetupStep = .welcome, onFinish: @escaping () async -> String?) {
        self.model = model
        self.onFinish = onFinish
        _step = LocalState(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(count: SetupStep.allCases.count, index: step.rawValue).padding(.top, 18)
            ZStack {
                content.id(step).transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: 600, height: 470)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeStep(slide: $slide)
        case .connect: StepFrame(title: tr("setup.connect.title")) { ConnectionSection(model: model) }
        case .organization: StepFrame(title: tr("setup.org.title")) { OrganizationSection(model: model) }
        case .exceptions: StepFrame(title: tr("setup.exceptions.title")) { ExceptionsSection(model: model) }
        case .general:
            StepFrame(title: tr("setup.general.title")) {
                GeneralSection(model: model)
                ValidationBanner(validation: model.validation)
            }
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

    private var footer: some View {
        HStack {
            if step == .welcome {
                Button(tr("setup.skip")) { go(to: .connect) }.buttonStyle(.borderless)
            } else {
                Button(tr("setup.back")) { goBack() }.disabled(isBusy)
            }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            Button(step == .general ? tr("setup.finish") : tr("setup.continue")) { Task { await advance() } }
                .keyboardShortcut(step == .exceptions ? nil : .defaultAction)
                .disabled(isBusy)
        }
        .padding(18)
    }

    private func advance() async {
        switch step {
        case .welcome:
            if slide < Self.slideCount - 1 { withAnimation(.spring(duration: 0.4)) { slide += 1 } } else { go(to: .connect) }
        case .connect:
            isBusy = true
            let valid = await model.validateConnection()
            isBusy = false
            if valid { go(to: .organization) }
        case .organization: go(to: .exceptions)
        case .exceptions: go(to: .general)
        case .general:
            isBusy = true
            if let failure = await onFinish() { model.reportFailure(failure) }
            isBusy = false
        }
    }

    private func goBack() {
        guard let previous = SetupStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    private func go(to next: SetupStep) {
        movingForward = next.rawValue > step.rawValue
        withAnimation(.spring(duration: 0.45)) { step = next }
    }
}

private struct StepFrame<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: position == index ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.4), value: index)
    }
}

private struct WelcomeStep: View {
    @Binding var slide: Int

    private let slides = [
        ("setup.welcome.1.title", "setup.welcome.1.body"),
        ("setup.welcome.2.title", "setup.welcome.2.body"),
        ("setup.welcome.3.title", "setup.welcome.3.body"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            PulsingIcon()
            VStack(spacing: 8) {
                Text(tr(slides[slide].0)).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(tr(slides[slide].1)).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .id(slide)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            HStack(spacing: 6) {
                ForEach(0 ..< slides.count, id: \.self) { position in
                    Circle().fill(position == slide ? Color.accentColor : Color.primary.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.45), value: slide)
    }
}

private struct PulsingIcon: View {
    @LocalState private var animate = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.orange, lineWidth: 2)
                .frame(width: 84, height: 84)
                .scaleEffect(animate ? 1.7 : 1)
                .opacity(animate ? 0 : 0.6)
            RoundedRectangle(cornerRadius: 20).fill(Color.orange.gradient)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "arrow.triangle.branch").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white))
                .overlay(alignment: .topTrailing) {
                    Text("3").font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                        .offset(x: 10, y: -8)
                }
        }
        .frame(height: 130)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { animate = true }
        }
    }
}
