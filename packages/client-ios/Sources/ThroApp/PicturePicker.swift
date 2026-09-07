import SwiftUI
import PhotosUI
import ThroTokens
import ThroDesign
import ThroJournal

// Choosing a picture, for anything that can have one (PD-014).
//
// The founder: *"no option for profile pictures for players, clubs, leagues or tournaments yet."*
// Correct on every one of the four, and the cause was the same in each case: the code existed and
// nothing could reach it.
//
// A **club, league or tournament** — one stored kind, so one screen serves all three — had a badge
// picker inside `EditClubScreen`. `ClubRoute` had no case for that screen. Nothing in `ClubsFlow`
// constructed it, `ClubScreen.onEdit` was never passed, and its `badge:` parameter was never given
// one either. So no club on a phone could be renamed, recoloured, given a badge or deleted.
//
// A **member** had `ClubStore.setAvatar`: public, tested, refusing a picture for anybody not
// established as an adult — and never called from anywhere.
//
// **Nothing was going to catch either.** No test in this repository constructs a screen; they hold
// the stores and the rules underneath. So every green tick was true — about code that nothing could
// open. `tools/check_screens_reachable.py` now fails on a screen nothing constructs and on a route
// case nothing assigns, which is the shape of both of these and of the two before them.

/// One picture, chosen and shown as the thing itself will be drawn.
///
/// **It refuses before it offers.** Where a picture is not allowed there is no picker at all, only
/// the reason. A control whose only outcome is a refusal is worse than no control, and here it would
/// be worse than cosmetic: the refusal exists because nobody under 18 — or of unestablished age —
/// has a picture in THRØ.
struct PicturePicker: View {
    /// What the mark looks like without a picture, so it is the same object either way.
    enum Subject {
        /// A club, league or tournament: `Badge`'s rounded square in its own colour.
        case organisation(initials: String, accent: Color?)
        /// A person: the circle `PersonMark` draws.
        case person(initials: String)
    }

    let subject: Subject
    let size: CGFloat
    /// What is stored now, if anything.
    let current: Image?
    /// Why a picture is not allowed, or nil when it is. Shown *instead of* the picker, never behind
    /// a disabled one.
    let refusedBecause: String?
    /// The chosen bytes. `removed` says the stored one should go — the two are separate because
    /// "nothing picked" and "take away what is there" are different instructions.
    @Binding var picked: Data?
    @Binding var removed: Bool

    @State private var item: PhotosPickerItem?
    @State private var problem: String?

    /// Written out rather than left to the synthesised memberwise initialiser, which the private
    /// `@State` above would otherwise make private too — and this is called from two other files.
    init(subject: Subject, size: CGFloat, current: Image?, refusedBecause: String?,
         picked: Binding<Data?>, removed: Binding<Bool>) {
        self.subject = subject
        self.size = size
        self.current = current
        self.refusedBecause = refusedBecause
        self._picked = picked
        self._removed = removed
    }

    private var preview: Image? {
        if removed { return nil }
        if let picked, let image = Image.thro(data: picked) { return image }
        return current
    }

    /// A club wears a badge and a person has a picture. Same control, and the screen still uses the
    /// word the thing is actually called.
    private var noun: String {
        if case .organisation = subject { return "badge" }
        return "picture"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            HStack(alignment: .top, spacing: ThroSpacing.spacing4) {
                mark
                if let refusedBecause {
                    Text(refusedBecause)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
                        PhotosPicker(selection: $item, matching: .images) {
                            Text(preview == nil ? "Choose a \(noun)" : "Change \(noun)")
                                .thro(ThroTypography.label.weight(.semibold))
                                .foregroundStyle(ThroColor.colorTextBrand)
                        }
                        if preview != nil {
                            Button {
                                removed = true
                                picked = nil
                                item = nil
                            } label: {
                                Text("Remove \(noun)")
                                    .thro(ThroTypography.label.weight(.semibold))
                                    .foregroundStyle(ThroColor.colorStatusError)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            // A photograph that could not be read is said so, rather than a picker that appears to
            // have done nothing.
            if let problem {
                Text(problem)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorStatusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // `.task(id:)` rather than `.onChange`: one spelling on every version this app supports, it
        // is already async, and it cancels itself if the picker changes again while a large
        // photograph is still loading.
        .task(id: item) {
            guard let item else { return }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    problem = "That picture could not be read."
                    return
                }
                picked = data
                removed = false
                problem = nil
            } catch {
                problem = "That picture could not be read: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch subject {
        case let .organisation(initials, accent):
            Badge(initials, size: size, accent: accent, image: preview)
        case let .person(initials):
            PersonMark(initials: initials, size: size, picture: preview)
        }
    }
}

/// Why this member may not have a picture, or nil when they may (PD-014).
///
/// **The rule is not restated here.** `ImagePolicy.mayHavePicture` answers, exactly as it answers
/// for the store, so a picker cannot drift into offering something `ClubBook.setAvatar` will refuse.
/// What this adds is the sentence, and the sentence is the point: "not allowed" teaches an admin
/// nothing, while naming the reason tells them that recording an age is what changes one case and
/// that nothing changes the other.
enum PicturePolicy {
    static func refusal(for band: AgeBand) -> String? {
        guard !ImagePolicy.mayHavePicture(ageBand: band.rawValue) else { return nil }
        switch band {
        case .adult:
            // Unreachable while the two agree, and deliberately not a crash: if the policy ever
            // stops allowing adults, the screen refuses rather than offering what the store rejects.
            return "No picture. THRØ is not storing pictures for this club's members."
        case .minor:
            return "No picture. Nobody recorded as under 18 has one — that is not a setting, and "
                 + "there is nothing here that turns it on."
        case .unknown:
            // Worded for both places it is shown: a club member whose age was never given, and a
            // person on this phone, for whom there is nowhere to give one at all.
            return "No picture. THRØ shows one only for somebody it knows to be an adult, and no "
                 + "age has been recorded here. What is not known is whether this is a child, so "
                 + "the careful answer is the one taken. **A picture arrives with an account** "
                 + "(PD-023), where the person in the photograph answers for their own age — which "
                 + "is the one person who should."
        }
    }
}
