import SwiftUI
import UniformTypeIdentifiers
import ThroTokens
import ThroDesign
import ThroJournal
import ThroPlay

/// Settings: whoever is signed in, then the settings themselves in three small groups, each a page.
///
/// **It was grey rows on a system list, with the section titles sat on the row above.** The founder:
/// *"the spacing on settings page is really ugly & design is too colour palette & style, branding
/// & design needs to be aligned throughout our E2E journey."* So it is drawn the way Home and the
/// You tab already are (`AccountDesign.swift`): the brand field at the top, the slate for the
/// person, raised cards for the rows, sections `spaceSectionGap` apart.
///
/// **Only what is true of this build appears**, and every setting keeps the explanation it had —
/// one tap in, under the control it explains, rather than all of it at once on the index.
public struct SettingsScreen: View {
    @AppStorage(Appearance.storageKey) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(ScoringPreferences.keepScreenAwakeKey) private var keepScreenAwake: Bool = true
    /// Which keypad the scoring screen offers. Held here as well as on the rail because a setting
    /// that only exists inside a match is a setting nobody finds before their first match.
    @AppStorage(ScoringPreferences.entryModeKey) private var entryModeRaw: String
        = ScoringEntryMode.default.rawValue
    @AppStorage(ThroHaptics.enabledKey) private var haptics: Bool = true
    @AppStorage(OpeningPreferences.soundKey) private var openingSound: Bool = true
    @AppStorage(OpeningPreferences.hapticsKey) private var openingHaptics: Bool = true
    @AppStorage(ThroSpotlight.enabledKey) private var spotlight: Bool = true
    /// PD-017's neighbour: what the phone can say about how the app performed on it. **Off by
    /// default**, because this is the one thing in the app the player gains nothing from — theirs
    /// to turn on rather than theirs to discover and turn off.
    @AppStorage(ThroDiagnostics.enabledKey) private var diagnostics: Bool = false
    private let onBack: () -> Void
    private let onReplayOpening: (() -> Void)?
    private let onAccount: (() -> Void)?
    /// Whoever is signed in, as the You tab's slate says it, and their picture where this phone
    /// holds one.
    private let account: YouScreen.Account
    private let picture: Image?
    private let organisationCount: () -> Int
    private let onClearOrganisations: (() -> Void)?
    @State private var confirmingClear = false
    /// PD-017. Where the file comes from and what the file system says about backups. Closures
    /// rather than the stores themselves, so Settings stays a screen and not a second owner of the
    /// device's data — and so a test can drive both without a journal on disk.
    private let backupState: () -> BackupPolicy.State
    private let makeExport: (() throws -> URL)?
    /// What the diagnostics folder holds, and how to empty it. Closures for the same reason the
    /// two above are: Settings is a screen, not a second owner of the device's data.
    private let diagnosticsHeld: () -> ThroDiagnostics.Held
    private let onForgetDiagnostics: () -> Void
    /// What this phone can currently show of everything the build added. Async because two of the
    /// answers — whether notifications are allowed, and what is pending — only come back that way.
    private let readinessFacts: @MainActor () async -> ThroReadiness.Facts
    /// Where the readiness screen sends somebody when a row has somewhere to send them.
    private let onGoReadiness: (ThroReadiness.Go) -> Void
    @State private var showingReadiness = false
    @State private var exported: URL?
    @State private var exportProblem: String?
    @State private var picking = false
    @State private var inspection: ExportInspection?
    /// Which page of Settings is open, or nil for the index.
    @State private var page: Page?

    public init(onBack: @escaping () -> Void, onReplayOpening: (() -> Void)? = nil,
                onAccount: (() -> Void)? = nil, account: YouScreen.Account = .none, picture: Image? = nil,
                organisationCount: @escaping () -> Int = { 0 }, onClearOrganisations: (() -> Void)? = nil,
                backupState: @escaping () -> BackupPolicy.State = { .unknown("no data folder in this build") },
                makeExport: (() throws -> URL)? = nil,
                diagnosticsHeld: @escaping () -> ThroDiagnostics.Held = { .init(count: 0, bytes: 0, newest: nil) },
                onForgetDiagnostics: @escaping () -> Void = {},
                readinessFacts: @escaping @MainActor () async -> ThroReadiness.Facts = { await ThroReadiness.probe(app: .init()) },
                onGoReadiness: @escaping (ThroReadiness.Go) -> Void = { _ in }) {
        self.onBack = onBack
        self.onReplayOpening = onReplayOpening
        self.onAccount = onAccount
        self.account = account
        self.picture = picture
        self.organisationCount = organisationCount
        self.onClearOrganisations = onClearOrganisations
        self.backupState = backupState
        self.makeExport = makeExport
        self.diagnosticsHeld = diagnosticsHeld
        self.onForgetDiagnostics = onForgetDiagnostics
        self.readinessFacts = readinessFacts
        self.onGoReadiness = onGoReadiness
    }

    private var appearance: Binding<Appearance> {
        Binding(get: { Appearance(stored: appearanceRaw) }, set: { appearanceRaw = $0.rawValue })
    }

    /// The stored notation as the value the control works in. The same shape as `appearance`, for
    /// the same reason: `@AppStorage` holds a string, because that is what survives a build that
    /// does not know a value, and every reader turns it back into the type at the edge.
    private var entryMode: Binding<ScoringEntryMode> {
        Binding(get: { ScoringEntryMode(stored: entryModeRaw) }, set: { entryModeRaw = $0.rawValue })
    }

    public var body: some View {
        Group {
            if let page {
                settingsPage(page)
            } else {
                VStack(spacing: 0) {
                    // No eyebrow: the brand field already says whose screen this is, and the line
                    // it took was a line the list below did not get.
                    BoardHeader(title: "Settings", onBack: onBack)
                    ScrollView {
                        settingsIndex
                            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                            .padding(.top, ThroSpacing.spacing5)
                            .padding(.bottom, ThroSpacing.spacing7)
                    }
                }
            }
        }
        // The screen arrives (PD-027): one beat, on the design's own curve,
        // withdrawn entirely under Reduce Motion.
        .throEntrance(0)
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            inspection = SettingsScreen.inspect(result)
        }
        .sheet(isPresented: $showingReadiness) {
            // The sheet closes itself before the route is taken. It sits over Settings, which sits
            // over the tabs, so leaving it open would put the destination behind two screens the
            // player never asked to still be there.
            ReadinessScreen(onBack: { showingReadiness = false }, gather: readinessFacts) { go in
                showingReadiness = false
                onGoReadiness(go)
            }
        }
    }

    // MARK: - the index
    //
    // **Settings was one scroll with a paragraph under every row**, and then an index whose section
    // titles sat on the hairline of the row above. Now: the person first, on the slate, because the
    // account is the row people come for; then three groups of what the settings are about —
    // playing, this phone, your darts — each row a page with its explanation inside it.

    /// A page of Settings. The order is the order of the index.
    enum Page: String, Identifiable, CaseIterable {
        case appearance, scoring, opening, search, data, discover, performance, build
        var id: String { rawValue }

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .scoring: return "Scoring"
            case .opening: return "The opening"
            case .search: return "Search"
            case .data: return "Your darts"
            // Short enough to sit on one line of a row; what it clears is the line under it.
            case .discover: return "Clear what Discover keeps"
            case .performance: return "How the app performs"
            case .build: return "This build"
            }
        }

        /// One line, so the index says what is behind a row without opening it.
        var summary: String {
            switch self {
            case .appearance: return "Light, dark or the phone's"
            case .scoring: return "Notation, screen and haptics"
            case .opening: return "Sound and haptics at launch"
            case .search: return "What THRØ puts in Spotlight"
            case .data: return "Export, backup and what a file holds"
            case .discover: return "Teams, leagues and tournaments on this phone"
            case .performance: return "Off unless you turn it on"
            case .build: return "Version, fonts and what is built"
            }
        }

        var icon: ThroIcon {
            switch self {
            case .appearance: return .eye
            case .scoring: return .target
            case .opening: return .play
            case .search: return .search
            case .data: return .filePen
            case .discover: return .users
            case .performance: return .clock
            case .build: return .info
            }
        }
    }

    @ViewBuilder private var settingsIndex: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spaceSectionGap) {
            AccountSlate(account: account, picture: picture, action: onAccount)
            CardGroup("Playing") {
                row(.appearance)
                CardDivider()
                row(.scoring)
                CardDivider()
                row(.opening)
            }
            CardGroup("This phone") {
                // The readiness screen is not a page of settings, it is an answer to "can I even see
                // this on my phone", so it opens as its own sheet rather than a page.
                CardRow(icon: .circleCheck, label: "What you can see on this phone",
                        value: "Every surface, and what is stopping each") { showingReadiness = true }
                CardDivider()
                row(.search)
                CardDivider()
                row(.performance)
            }
            CardGroup("What this phone keeps") {
                row(.data)
                if onClearOrganisations != nil {
                    CardDivider()
                    row(.discover)
                }
            }
            buildLine
        }
    }

    private func row(_ page: Page) -> some View {
        CardRow(icon: page.icon, label: page.title, value: page.summary) { self.page = page }
    }

    /// Which build this is, said once at the foot of the index and opened from there — the one
    /// fact the runbook asks for, where a person looks for it.
    private var buildLine: some View {
        Button { page = .build } label: {
            HStack(spacing: ThroSpacing.spacing2) {
                ThroMark().fill(ThroColor.colorTextSecondary).frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text("THRØ \(BuildInfo.label)")
                    .thro(ThroTypography.metadata.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
                Icon(.chevronRight, size: 12).foregroundStyle(ThroColor.colorTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .throTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusControl))
        .accessibilityLabel("This build, \(BuildInfo.label)")
    }

    // MARK: - the pages

    @ViewBuilder private func settingsPage(_ page: Page) -> some View {
        VStack(spacing: 0) {
            BoardHeader(title: page.title, eyebrow: "Settings", onBack: { self.page = nil })
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spaceSectionGap) {
                    switch page {
                    case .appearance: appearancePage
                    case .scoring: scoringPage
                    case .opening: openingPage
                    case .search: searchPage
                    case .data: dataPage
                    case .discover: discoverPage
                    case .performance: performancePage
                    case .build: buildPage
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing5)
                .padding(.bottom, ThroSpacing.spacing7)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }

    @ViewBuilder private var appearancePage: some View {
        CardGroup(footnote: "Every screen follows this, scoring included. System follows the phone.") {
            CardPad { SegmentedControl(Appearance.allCases.map { ($0, $0.label) }, selection: appearance) }
        }
    }

    @ViewBuilder private var scoringPage: some View {
        // **How a visit is entered**, and the reason it is here as well as on the scoring rail: the
        // founder asked for both notations, and a control that exists only inside a match is one
        // nobody finds before their first match. The rail's switch changes the same stored value,
        // so the two cannot drift. `SegmentedControl` and not SwiftUI's `Picker(.segmented)`: a
        // `UISegmentedControl` is 32 points tall, below the 44-point floor this app holds every
        // other control to.
        CardGroup("How a visit is entered",
                  footnote: SettingsScreen.entryModeNote(ScoringEntryMode(stored: entryModeRaw))) {
            CardPad {
                SegmentedControl(ScoringEntryMode.allCases.map { ($0, $0.label) }, selection: entryMode)
            }
        }
        // The export's Settings lists this row under Scoring, default On.
        CardGroup("Screen", footnote: "While scoring, the phone does not sleep between visits.") {
            CardToggleRow(icon: .smartphone, label: "Keep screen awake", isOn: $keepScreenAwake)
        }
        // PD-015. Default on: the point of a haptic at a dartboard is that it is felt while the
        // player is looking at the board. Off is offered because a phone buzzing in a pocket through
        // a match is somebody else's idea of help.
        CardGroup("Haptics",
                  footnote: "A light tap on every key, a firmer one when a visit is saved, and its own "
                      + "sensation for a bust, a checkout coming up, an undo, a leg, and the match — so "
                      + "the ones that matter are felt without looking at the phone.") {
            CardToggleRow(icon: .target, label: "Haptics", isOn: $haptics)
        }
    }

    @ViewBuilder private var openingPage: some View {
        // PD-007 v2: the throw that opens the app, its sound and its haptic. Sound goes through the
        // ambient session, so the silent switch always wins.
        CardGroup(footnote: "The silent switch silences the sound whatever this says. Reduce Motion "
                      + "shows the finished mark instead of the throw.") {
            CardToggleRow(icon: .radio, label: "Sound", isOn: $openingSound)
            CardDivider()
            CardToggleRow(icon: .smartphone, label: "Haptic on the strike", isOn: $openingHaptics)
        }
        if let onReplayOpening {
            CardGroup {
                CardRow(icon: .play, label: "Play the opening again", leads: false, action: onReplayOpening)
            }
        }
    }

    @ViewBuilder private var searchPage: some View {
        CardGroup(footnote: "Your matches, the people who play here and your teams appear in this "
                      + "iPhone's own search. The index is on the phone, is never sent to Apple, and "
                      + "is not shared with your other devices. Turning this off removes what is "
                      + "already there.") {
            CardToggleRow(icon: .search, label: "Find these on this phone", isOn: $spotlight)
        }
    }

    @ViewBuilder private var performancePage: some View {
        CardGroup(footnote: "iOS can tell THRØ how long it took to open, when it froze and how much "
                      + "memory it used, at most once a day. The reports are written to this phone and "
                      + "go nowhere. Turning this off deletes the ones already collected.") {
            CardToggleRow(icon: .shield, label: "Collect performance reports", isOn: $diagnostics)
            if diagnostics {
                CardDivider()
                CardPad {
                    Text(ThroDiagnostics.sentence(diagnosticsHeld()))
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Off means gone, not merely stopped. A switch that left the collected reports behind
        // would be a switch that lies, which is the rule the Spotlight switch already follows.
        .onChange(of: diagnostics) { _, on in if !on { onForgetDiagnostics() } }
    }

    @ViewBuilder private var dataPage: some View {
        // PD-017. Both halves are told. A player who learns their darts are in iCloud from a support
        // article rather than from the app has been failed twice — and one who assumes they are,
        // and is wrong, has been failed worse.
        let state = backupState()
        CardGroup("Backup", footnote: BackupPolicy.sentence(state), alarming: !state.isIncluded) {
            CardInfoRow(icon: state.isIncluded ? .cloudCheck : .cloudOff,
                        label: "In the phone's backup", value: state.isIncluded ? "Yes" : "No")
        }
        if let makeExport {
            CardGroup("Export",
                      footnote: "One file with every match, every visit as written — corrections and "
                          + "all — and every team this phone keeps. Nothing is sent anywhere: you choose "
                          + "where it goes. Pictures are not in it; the file names the ones this phone holds.") {
                CardRow(icon: .filePen, label: "Export everything", leads: false) {
                    do {
                        exported = try makeExport()
                        exportProblem = nil
                    } catch {
                        exported = nil
                        exportProblem = "\(error)"
                    }
                }
                if let exported {
                    CardDivider()
                    // A row's face rather than a line of text: a bare `Text` here once had no pressed
                    // state and a hit area the size of the ink, which `check_controls_react` now
                    // holds every `ShareLink` to.
                    ShareLink(item: exported) {
                        HStack(spacing: ThroSpacing.spacing3) {
                            IconTile(icon: .circleCheck)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save or send it")
                                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                Text(exported.lastPathComponent)
                                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                            }
                            Spacer(minLength: ThroSpacing.spacing2)
                        }
                        .padding(.horizontal, ThroSpacing.spacing4)
                        .padding(.vertical, ThroSpacing.spacing3)
                        .frame(maxWidth: .infinity, minHeight: CardRow.height, alignment: .leading)
                        .throRowTapTarget()
                    }
                    .buttonStyle(ThroPressStyle(radius: 0, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
                }
            }
            if let exportProblem {
                Snackbar(exportProblem, tone: .error)
            }
            // PD-017. An export nobody can read back is a file a player has to *trust* worked. This
            // opens one and says what is in it — and writes nothing, which is the decision rather
            // than a limitation.
            CardGroup("Check a file",
                      footnote: "Checking a file reads it and nothing else. Bringing one back into the app "
                          + "is not built: merging two journals is the same problem as syncing two phones, "
                          + "and doing it badly would leave a record that lies about what this phone wrote.") {
                CardRow(icon: .search, label: "Check a file", value: "Open an export and see what is in it",
                        leads: false) { picking = true }
            }
            if let inspection {
                inspected(inspection)
            }
        }
    }

    @ViewBuilder private var discoverPage: some View {
        if let onClearOrganisations {
            let n = organisationCount()
            CardGroup(footnote: "Removes every team, league and tournament on this phone, with their "
                          + "rosters, fixtures and results. Your matches and the people you have played "
                          + "stay: they are history, not organisations.") {
                if n == 0 {
                    CardInfoRow(icon: .users, label: "Teams, leagues and tournaments", value: "None on this phone")
                } else {
                    CardRow(icon: .circleX, label: "Remove every team, league and tournament",
                            value: "\(n) organisation\(n == 1 ? "" : "s") on this phone",
                            tone: .destructive, leads: false) { confirmingClear = true }
                }
            }
            .confirmationDialog("Remove every organisation on this phone?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Remove \(n) organisation\(n == 1 ? "" : "s")", role: .destructive) {
                    onClearOrganisations(); confirmingClear = false
                }
                Button("Keep them", role: .cancel) { confirmingClear = false }
            } message: {
                Text("Rosters, fixtures and results on this phone go with them. Matches and people stay. This cannot be undone.")
            }
        }
    }

    @ViewBuilder private var buildPage: some View {
        CardGroup {
            CardInfoRow(icon: .info, label: "Build", value: BuildInfo.label)
            CardDivider()
            CardInfoRow(icon: .smartphone, label: "Matches", value: "Kept on this phone")
            CardDivider()
            // PD-040: a finished match can be sent to THRØ, from the Live tab, by somebody signed
            // in. This row said "Not built" after it was.
            CardInfoRow(icon: .cloudCheck, label: "Sending a match to THRØ", value: "From the Live tab")
            CardDivider()
            CardInfoRow(icon: .pencilLine, label: "Fonts", value: ThroFont.customFacesRegistered ? "Embedded" : "System face")
        }
    }

    // MARK: - the rest

    /// What each notation costs and buys, in the words a player would use.
    ///
    /// **It says the cost as well as the gain**, because a setting that only lists advantages is
    /// one somebody switches and then quietly regrets. Entering darts is more taps and it takes
    /// room off the board on a small phone; what it buys is that a checkout stops interrupting to
    /// ask questions the app could have worked out.
    static func entryModeNote(_ mode: ScoringEntryMode) -> String {
        switch mode {
        case .visitTotal:
            return "Type the total of three darts. Fewer taps, and the way every darts app works — "
                 + "but a checkout stops to ask how many darts it took and how many were at a "
                 + "double, because nothing else can know."
        case .perDart:
            return "Tap each dart as it lands. A checkout asks nothing, because the answers are in "
                 + "what you entered — and your checkout percentage becomes exact instead of a "
                 + "range. It is more taps, and on a small phone the score steps down a size to "
                 + "make room for the three darts."
        }
    }

    /// Reads the picked file and describes it. Static and taking the importer's own result so the
    /// whole path — including the two failures that are not the file's fault — is testable without
    /// a file picker.
    static func inspect(_ result: Result<URL, Error>, thisDevice: DeviceId? = nil) -> ExportInspection {
        switch result {
        case let .failure(error):
            return .refused("That file could not be opened: \(error.localizedDescription)")
        case let .success(url):
            // A file chosen outside the app's own container needs its scope claimed for the read
            // and released after it, whether or not the read succeeds.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                return .refused("That file could not be opened.")
            }
            return ExportInspection.of(data, thisDevice: thisDevice)
        }
    }

    @ViewBuilder
    private func inspected(_ inspection: ExportInspection) -> some View {
        switch inspection {
        case let .readable(file):
            VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                Tag("Readable", tone: .success)
                Text(file.summary)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(file.fromThisDevice
                     ? "Written by this phone."
                     : "Written by a different phone. That is normal for a file you have kept or been sent.")
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if file.assetsNotIncluded > 0 {
                    Text("It names \(file.assetsNotIncluded) picture\(file.assetsNotIncluded == 1 ? "" : "s") it does not carry.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                }
            }
            .padding(ThroSpacing.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard).fill(ThroColor.colorBackgroundRaised))
            .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard).strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
        case let .refused(why):
            Snackbar(why, tone: .error)
        }
    }
}
