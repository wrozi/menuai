//
//  OnboardingView.swift
//  menuai
//
//  Matched to Cal AI's actual onboarding: a welcome with a drawn phone, one
//  question per screen with a chart, a thank-you and a without/with
//  comparison spaced between them, a celebration, a "setting up" moment that
//  makes the answers feel built rather than saved, and a summary with
//  editable tiles before "Let's get started!".
//
//  The tone shifts on purpose: calm and terse during the questions, warm at
//  the milestones. That is the reference's own pattern.
//
//  Every screen is choreographed once, on appear: one `shown` flag flips
//  about 120 ms after the step has slid in, and each piece follows it with
//  its own delay. Nothing loops here, nothing waits on the Continue button,
//  and with Reduce Motion on the whole sequence collapses to one short fade.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// In funnel order; the raw value is what the STEP debug hook takes.
    private enum Step: Int, CaseIterable {
        case welcome
        case language, diet, chart, trust, goal, allergies, spice, adventure, comparison, cuisines, done
        case setup, summary

        /// Steps that show the header bar; the bar's progress runs over these.
        static let tracked: [Step] = Array(allCases[Step.language.rawValue ... Step.done.rawValue])
        var showsHeader: Bool { Step.tracked.contains(self) }
        var progress: Double {
            guard let i = Step.tracked.firstIndex(of: self) else { return 1 }
            return Double(i + 1) / Double(Step.tracked.count)
        }
    }

    @State private var step: Step = {
        #if DEBUG
        if let s = SelfTest.requestedStep, let step = Step(rawValue: s) { return step }
        #endif
        return .welcome
    }()
    @State private var customAllergy = ""
    @State private var goingBack = false
    @State private var isTransitioning = false
    @State private var returnToSummary = false

    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Theme.gentle
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: goingBack ? .leading : .trailing).combined(with: .opacity),
            removal: .move(edge: goingBack ? .trailing : .leading).combined(with: .opacity)
        )
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if step.showsHeader {
                OnboardingHeader(progress: step.progress, showsBack: true) { go(back: true) }
            }

            ZStack {
                screen(prefs: $store.preferences)
                    .id(step)
                    .transition(stepTransition)
            }
            .animation(stepAnimation, value: step)

            if step != .setup { controls }
        }
        .background(Theme.bg)
    }

    // MARK: - Routing

    @ViewBuilder
    private func screen(prefs: Binding<UserPreferences>) -> some View {
        switch step {
        case .welcome: welcome
        case .language: languageStep(prefs: prefs)
        case .diet: dietStep(prefs: prefs)
        case .chart: chart
        case .trust: trust
        case .goal: goalStep(prefs: prefs)
        case .allergies: allergyStep(prefs: prefs)
        case .spice: spiceStep(prefs: prefs)
        case .adventure: adventureStep(prefs: prefs)
        case .comparison: comparison
        case .cuisines: cuisineStep(prefs: prefs)
        case .done: done
        case .setup: SetupView(prefs: prefs.wrappedValue) { go(back: false) }
        case .summary: summary(prefs: prefs.wrappedValue)
        }
    }

    private func go(back: Bool) {
        commitPendingAllergy()
        if returnToSummary {
            returnToSummary = false
            move(to: .summary, back: back)
            return
        }
        let all = Step.allCases
        guard let i = all.firstIndex(of: step) else { return }
        let next = back ? i - 1 : i + 1
        guard all.indices.contains(next) else { return }
        // Never step back into the loading screen; skip over it.
        var target = all[next]
        if back, target == .setup { target = .done }
        move(to: target, back: back)
    }

    /// The outgoing view keeps the transition it last rendered with, so the
    /// direction has to land in its own update before `step` changes.
    private func move(to target: Step, back: Bool) {
        guard !isTransitioning, target != step else { return }
        isTransitioning = true
        goingBack = back
        Task { @MainActor in
            withAnimation(stepAnimation) { step = target }
            // Continue persists across steps, so VoiceOver would otherwise
            // stay on it and never hear the new question.
            AccessibilityNotification.ScreenChanged().post()
            // The slide's length, or the fade's: input never waits on
            // motion that is not happening.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 450))
            isTransitioning = false
        }
    }

    private func commitPendingAllergy() {
        guard step == .allergies else { return }
        @Bindable var store = store
        $store.preferences.allergies.add(from: $customAllergy)
    }

    /// A pencil on the summary: back to that question, and the next Continue
    /// returns here instead of moving on.
    private func jump(_ target: Step) {
        guard !isTransitioning, target != step else { return }
        returnToSummary = true
        move(to: target, back: true)
    }

    /// One button for every step, its label swapped outright: two buttons
    /// crossfading laid "Get started" over "Continue" for a few frames.
    private var controls: some View {
        PillButton(title: buttonTitle) {
            if step == .summary { store.completeOnboarding() } else { go(back: false) }
        }
        .contentTransition(.identity)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: "Get started"
        case .summary: "Let's get started!"
        default: "Continue"
        }
    }

    // MARK: - Welcome

    /// The phone fills the space and the title sits just above the
    /// button, as in the reference. At the accessibility sizes the text
    /// can outgrow the slack, so it scrolls there instead.
    ///
    /// The phone runs its own choreography (scale in, menu lines, brackets
    /// locking on); the words rise once it has settled.
    private var welcome: some View {
        Staged { shown in
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        DeviceMockup(animated: !reduceMotion).padding(.top, Theme.Space.m)
                        welcomeText(shown: shown)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Space.l)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 0) {
                    DeviceMockup(animated: !reduceMotion).padding(.top, Theme.Space.m)
                    Spacer(minLength: Theme.Space.l)
                    welcomeText(shown: shown).padding(.bottom, Theme.Space.m)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func welcomeText(shown: Bool) -> some View {
        VStack(spacing: Theme.Space.s) {
            Text("Know what to order")
                .scaledFont(size: 34, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
                .stageReveal(shown, delay: 0.55)
            Text("Any menu. Any language. Ranked for you.")
                .scaledFont(size: 17, relativeTo: .body)
                .foregroundStyle(Theme.inkSecondary)
                .stageReveal(shown, delay: 0.65)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Space.l)
    }

    // MARK: - Questions

    private func languageStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "Which language do you read?", subtitle: "Every menu, in this language.") { shown in
            Picker("Language", selection: prefs.displayLanguage) {
                ForEach(supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity, maxHeight: 210)
            .stageReveal(shown, delay: StageMotion.contentDelay)
        }
    }

    /// Text-only rows, centred, like the reference's short choices. The
    /// diet icons still mark the summary tile.
    private func dietStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "How do you eat?", subtitle: "Anything that clashes gets flagged.") { shown in
            VStack(spacing: Theme.Space.m) {
                ForEach(Array(Diet.allCases.enumerated()), id: \.element) { index, diet in
                    OptionRow(title: diet.label, isSelected: prefs.wrappedValue.diet == diet) {
                        prefs.wrappedValue.diet = diet
                    }
                    .stageReveal(shown, delay: StageMotion.rowDelay(index))
                }
            }
        }
    }

    private func goalStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "What are you going for?", subtitle: "Shows on every dish.") { shown in
            // The same rhythm as the rows, and the field wears an
            // unselected row's clothes: a sunken grey on the ground was too
            // close to it to read as a field.
            // Five rows plus the field: at the row rhythm the field sat cut
            // off by the button, so this step runs a step tighter.
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                StagedChoices(options: EatingGoal.choices, selection: prefs.goal.index, shown: shown, spacing: Theme.Space.s)
                GoalNoteField(text: prefs.goalNote)
                    .stageReveal(shown, delay: StageMotion.rowDelay(EatingGoal.choices.count))
            }
        }
    }

    private func allergyStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "Anything you can't eat?", subtitle: "Flagged on every menu.") { shown in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                StagedChips(options: CommonAllergen.options(including: prefs.wrappedValue.allergies),
                            selected: Set(prefs.wrappedValue.allergies), shown: shown) {
                    prefs.allergies.toggle($0)
                }
                AddField(placeholder: "Something else", text: $customAllergy) { prefs.allergies.add(from: $customAllergy) }
                    .stageReveal(shown, delay: StageMotion.rowDelay(StageMotion.staggered))
                Text("Always confirm with staff for anything serious.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .stageReveal(shown, delay: StageMotion.rowDelay(StageMotion.staggered + 1))
            }
        }
    }

    private func spiceStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "How much heat?", subtitle: "Nothing you'll regret.") { shown in
            StagedChoices(options: Choices.spice, selection: prefs.spiceTolerance, shown: shown)
        }
    }

    private func adventureStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "How adventurous?", subtitle: "No wrong answer.") { shown in
            StagedChoices(options: Choices.adventure, selection: prefs.adventurousness, shown: shown)
        }
    }

    private func cuisineStep(prefs: Binding<UserPreferences>) -> some View {
        StepScaffold(title: "Food you love", subtitle: "Picks lean this way.") { shown in
            StagedChips(options: cuisineOptions, selected: Set(prefs.wrappedValue.lovedCuisines), shown: shown) {
                prefs.lovedCuisines.toggle($0)
            }
        }
    }

    // MARK: - Between the questions

    /// The chart draws itself as soon as it is on screen (both curves, then
    /// the fills and the dots); the caption rises as the last dot pops.
    private var chart: some View {
        StepScaffold(title: "Designed to pick better every time") { shown in
            VStack(spacing: Theme.Space.l) {
                TrendChart(
                    title: "Ordering success rate",
                    ourLabel: "MenuAI",
                    theirLabel: "Guessing",
                    startLabel: "Meal 1",
                    endLabel: "Meal 20",
                    animated: !reduceMotion
                )
                // The habit loop's one line in onboarding.
                Text("Rate it. Every menu gets smarter.")
                    .scaledFont(size: 17, relativeTo: .body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .stageReveal(shown, delay: 1.15)
            }
            .padding(Theme.Space.l)
            .background(Theme.sectionCard, in: .rect(cornerRadius: Theme.Radius.section, style: .continuous))
            .padding(.top, Theme.Space.l)
        }
    }

    private var trust: some View {
        Celebration(
            icon: "hand.wave",
            title: "Thank you for trusting us!",
            subtitle: "Now let's personalise MenuAI for you…",
            gesture: .wave
        ) {
            PrivacyCard(title: "Nothing leaves your iPhone.", body: "Menus are read on it. Your allergies and taste stay here.")
                .padding(.horizontal, Theme.Space.xl)
        }
    }

    /// The outer card rises first; the ticks inside it follow on their own.
    private var comparison: some View {
        StepScaffold(title: "Order right, every time") { shown in
            ComparisonCard(
                withoutTitle: "Without MenuAI",
                without: ["Guess from a menu you can't read", "Miss what you're allergic to", "Order the same safe thing again"],
                withTitle: "With MenuAI",
                with: ["Every dish explained, in your language", "Allergies flagged before you order", "Picks that learn what you like"],
                animated: !reduceMotion
            )
            .padding(Theme.Space.l)
            .background(Theme.sectionCard, in: .rect(cornerRadius: Theme.Radius.section, style: .continuous))
            .padding(.top, Theme.Space.l)
            .stageReveal(shown, delay: StageMotion.contentDelay)
        }
    }

    // MARK: - Finish

    private var done: some View {
        Celebration(
            icon: "hand.thumbsup",
            badge: "All done!",
            title: "Time to rank your first menu!",
            gesture: .thumbsUp
        ) { EmptyView() }
    }

    /// The stamp draws itself, the title rises under it, the four tiles
    /// land one after another, and "Your info" comes last.
    private func summary(prefs: UserPreferences) -> some View {
        Staged { shown in
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    VStack(spacing: Theme.Space.m) {
                        // A stamp above the cards, not a second hero.
                        CheckStamp(animated: !reduceMotion)
                            .accessibilityHidden(true)
                        Text("Ready for any menu")
                            .scaledFont(size: 34, weight: .bold, relativeTo: .largeTitle)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .stageReveal(shown, delay: 0.55)
                    }
                    .padding(.top, Theme.Space.m)

                    SectionCard(title: "Your taste", subtitle: "You can edit this anytime") {
                        tasteGrid(prefs: prefs, shown: shown)
                    }
                    .stageReveal(shown, delay: 0.62)

                    SectionCard(title: "Your info") {
                        InnerCard {
                            VStack(alignment: .leading, spacing: Theme.Space.m) {
                                InfoRow(icon: "globe", label: "Reads in", value: prefs.displayLanguageName)
                                InfoRow(icon: "exclamationmark.triangle.fill", label: "Allergies",
                                        value: prefs.allergies.isEmpty ? "None" : prefs.allergies.joined(separator: ", "))
                                if !prefs.lovedCuisines.isEmpty {
                                    InfoRow(icon: "heart.fill", label: "Loves", value: prefs.lovedCuisines.joined(separator: ", "))
                                }
                            }
                        }
                    }
                    .stageReveal(shown, delay: 0.95)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Two-up until the tiles stop fitting a value beside each other; a
    /// column at the accessibility sizes.
    private func tasteGrid(prefs: UserPreferences, shown: Bool) -> some View {
        let pair = typeSize >= .accessibility1
            ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.s))
        return VStack(spacing: Theme.Space.s) {
            pair {
                SummaryTile(icon: prefs.diet.icon, tint: Theme.great, label: "Diet", value: prefs.diet.label) { jump(.diet) }
                    .stageReveal(shown, delay: Self.tileDelay(0), rise: 0, scale: 0.96)
                SummaryTile(icon: "target", tint: Theme.good, label: "Goal", value: prefs.goal.label) { jump(.goal) }
                    .stageReveal(shown, delay: Self.tileDelay(1), rise: 0, scale: 0.96)
            }
            .fixedSize(horizontal: false, vertical: true)
            pair {
                SummaryTile(icon: "flame.fill", tint: Theme.okay, label: "Heat",
                            value: Choices.labels.spice[min(max(prefs.spiceTolerance, 0), 3)]) { jump(.spice) }
                    .stageReveal(shown, delay: Self.tileDelay(2), rise: 0, scale: 0.96)
                SummaryTile(icon: "binoculars.fill", tint: Theme.star, label: "Adventure",
                            value: Choices.labels.adventure[min(max(prefs.adventurousness, 0), 3)]) { jump(.adventure) }
                    .stageReveal(shown, delay: Self.tileDelay(3), rise: 0, scale: 0.96)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The tiles start once their card is up, 60 ms apart.
    private static func tileDelay(_ index: Int) -> Double { 0.72 + Double(index) * 0.06 }
}

// MARK: - Choreography

/// The screens' shared timing. Every duration and delay here goes through
/// `Theme.paced` / `Animation.paced`, so the QA hook
/// (`MENUAI_SELFTEST_MOTION=slow`) stretches the whole choreography 3×.
private enum StageMotion {
    /// What every bespoke piece collapses to under Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// When a question's first row may start, after the title and subtitle.
    static let contentDelay: Double = 0.1
    /// Rows past this one arrive together — a long list must not feel slow.
    static let staggered = 6
    /// The reveal delay for row `index`: 30 ms apart, capped.
    static func rowDelay(_ index: Int) -> Double { contentDelay + Double(min(max(index, 0), staggered)) * 0.03 }

    /// Sleeps for the scaled interval; false when the view went away.
    static func pause(_ base: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(Theme.paced(base)))
            return true
        } catch {
            return false
        }
    }
}

/// Owns the one `shown` flag a screen's choreography runs off: false while
/// the step slides in, true about 120 ms later. Every step is rebuilt with
/// its own copy, so nothing replays and nothing leaks between steps.
private struct Staged<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        // Under Reduce Motion the whole screen arrives with the step's own
        // fade; a second fade queued behind it is what the setting removes.
        content(shown || reduceMotion)
            .task {
                if reduceMotion { shown = true; return }
                guard await StageMotion.pause(0.12) else { return }
                shown = true
            }
    }
}

/// Fades a piece in on `shown`, rising and/or scaling into place after its
/// delay. Under Reduce Motion it is the plain fade, at once.
private struct StageReveal: ViewModifier {
    let shown: Bool
    let delay: Double
    let rise: CGFloat
    let scale: CGFloat
    let animation: Animation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: settled ? 0 : rise)
            .scaleEffect(settled ? 1 : scale)
            .animation(reduceMotion ? StageMotion.fade : animation.paced.delay(Theme.paced(delay)), value: shown)
    }
}

private extension View {
    func stageReveal(_ shown: Bool, delay: Double = 0, rise: CGFloat = 14, scale: CGFloat = 1, animation: Animation = Theme.gentle) -> some View {
        modifier(StageReveal(shown: shown, delay: delay, rise: rise, scale: scale, animation: animation))
    }
}

/// `ChoiceList`'s rows, each revealed in turn. The wording still comes from
/// `Choices`; only the entrance is onboarding's.
private struct StagedChoices: View {
    let options: [(String, String, String)]
    @Binding var selection: Int
    let shown: Bool
    var spacing: CGFloat = Theme.Space.m

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                OptionRow(title: option.0, subtitle: option.1, icon: option.2, isSelected: selection == index) {
                    selection = index
                }
                .stageReveal(shown, delay: StageMotion.rowDelay(index))
            }
        }
    }
}

/// `ChipGrid` with the first few chips staggered and the rest arriving
/// together, so a long list never feels slow.
private struct StagedChips: View {
    let options: [String]
    let selected: Set<String>
    let shown: Bool
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                ToggleChip(text: option, isOn: selected.contains(option)) {
                    onTap(option)
                }
                .stageReveal(shown, delay: StageMotion.rowDelay(index), rise: 8, animation: Theme.snap)
            }
        }
    }
}

// MARK: - Setting up

/// The labour-illusion screen. A big percentage counts up, a gradient bar
/// fills, status text ticks through the stages, and a checklist gets ticked
/// off — so the answers feel built into something, not merely saved.
private struct SetupView: View {
    let prefs: UserPreferences
    let onComplete: () -> Void

    @State private var percent = 0

    /// Only what the picks are actually based on: a goal is listed when one
    /// was given, not ticked off for somebody who chose "No goal".
    private var items: [String] {
        var list = ["Language", "Diet"]
        if prefs.goal != .none { list.append("Goal") }
        return list + ["Allergies", "Heat", "Taste"]
    }

    private var status: String {
        switch percent {
        case ..<30: "Reading your answers…"
        case ..<60: "Learning your taste…"
        case ..<85: "Setting up allergy checks…"
        default: "Finishing up…"
        }
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer()

            Text("\(percent)%")
                .scaledFont(size: 76, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                // Snaps: a crossfade every tick ghosted the previous digit.
                .contentTransition(.identity)
                // The bar below already announces the percent.
                .accessibilityHidden(true)

            Text("We're setting everything\nup for you")
                .scaledFont(size: 30, weight: .bold, relativeTo: .title)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            GradientProgressBar(progress: Double(percent) / 100)
                .padding(.horizontal, Theme.Space.l)

            Text(status)
                .scaledFont(size: 17, relativeTo: .body)
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: status)

            ChecklistCard(title: "Picks based on", items: items, completed: min(items.count, percent * items.count / 100))
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)

            Spacer()
            Spacer()
        }
        .onChange(of: status) { _, new in
            AccessibilityNotification.Announcement(new).post()
        }
        .task {
            for value in 1 ... 100 {
                do { try await Task.sleep(for: .milliseconds(34)) } catch { return }
                withAnimation(.linear(duration: 0.03)) { percent = value }
            }
            // The summary's stamp gives the one success tap, on something
            // the user sees drawn.
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            onComplete()
        }
    }
}

// MARK: - Celebration screen

/// A milestone: the gradient ring around a light icon, an optional tan
/// "done" badge, the big title, a grey line under it and anything extra.
///
/// The ring scales in on its own; the icon pops into it, then makes its
/// gesture — a wave for the thank-you, a nudge for the thumbs-up — and the
/// badge, the words and the extra follow in that order.
private struct Celebration<Extra: View>: View {
    enum CelebrationGesture { case wave, thumbsUp, none }

    let icon: String
    var badge: String?
    let title: String
    var subtitle: String?
    var gesture: CelebrationGesture = .none
    @ViewBuilder var extra: Extra

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var iconShown = false
    @State private var waveAngle: Double = 0
    @State private var nudged = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                CelebrationRing(animated: !reduceMotion) {
                    Image(systemName: icon)
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(Theme.ink)
                        // Pivots near the wrist, not the palm's centre.
                        .rotationEffect(.degrees(waveAngle), anchor: UnitPoint(x: 0.5, y: 0.9))
                        .rotationEffect(.degrees(nudged ? -8 : 0))
                        .offset(y: nudged ? -6 : 0)
                        .scaleEffect(iconShown || reduceMotion ? 1 : 0.6)
                        .opacity(iconShown ? 1 : 0)
                }
                .padding(.top, Theme.Space.xl)
                .accessibilityHidden(true)

                VStack(spacing: Theme.Space.s) {
                    if let badge {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Theme.okay).frame(width: 20, height: 20)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.onAccent)
                            }
                            .accessibilityHidden(true)
                            Text(badge)
                                .scaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                                .foregroundStyle(Theme.ink)
                        }
                        .stageReveal(shown, delay: 0.7, rise: 0, scale: 0.8, animation: Theme.snap)
                    }
                    Text(title)
                        .scaledFont(size: 34, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .stageReveal(shown, delay: 0.8)
                    if let subtitle {
                        Text(subtitle)
                            .scaledFont(size: 20, relativeTo: .title3)
                            .foregroundStyle(Theme.inkSecondary)
                            .stageReveal(shown, delay: 0.9)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.l)

                extra
                    .stageReveal(shown, delay: 1.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollIndicators(.hidden)
        // Cancelled with the view, so a gesture never outlives its screen.
        .task { await choreograph() }
    }

    private func choreograph() async {
        if reduceMotion {
            withAnimation(StageMotion.fade) {
                shown = true
                iconShown = true
            }
            if gesture == .thumbsUp { Haptic.success() }
            return
        }

        guard await StageMotion.pause(0.12) else { return }
        shown = true

        guard await StageMotion.pause(0.2) else { return }
        withAnimation(Theme.snap.paced) { iconShown = true }
        if gesture == .thumbsUp { Haptic.success() }

        // Let the pop land before the hand moves; the ring's dots have
        // settled by then and the gesture owns its moment, with the words
        // riding its second half.
        guard await StageMotion.pause(0.2) else { return }
        switch gesture {
        case .wave:
            // Two waves: four half-swings, then back to rest.
            for angle in [-14.0, 14, -14, 14, 0] {
                withAnimation(.easeInOut(duration: Theme.paced(0.16))) { waveAngle = angle }
                guard await StageMotion.pause(0.16) else { return }
            }
        case .thumbsUp:
            withAnimation(.easeOut(duration: Theme.paced(0.12))) { nudged = true }
            guard await StageMotion.pause(0.12) else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).paced) { nudged = false }
        case .none:
            break
        }
    }
}

// MARK: - Question scaffold

/// Title, optional subtitle, content. No icon — the reference puts the
/// question straight under the header.
///
/// Owns the step's `shown` flag: the title rises first, the subtitle just
/// behind it, and the content gets the flag to stagger its own rows.
private struct StepScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        Staged { shown in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(title)
                            .scaledFont(size: 32, weight: .bold, relativeTo: .largeTitle)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .stageReveal(shown)
                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.body)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .stageReveal(shown, delay: 0.05)
                        }
                    }

                    content(shown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
