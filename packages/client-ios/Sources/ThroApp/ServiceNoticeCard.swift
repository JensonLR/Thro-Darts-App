import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

/// The notice about people's information, on Home (PD-094).
///
/// It is the one card on Home that THRØ put there rather than something on the phone, so it says what it is before
/// anything else: the warning surface, then the title and the summary in the words for this reader's age. The full
/// account is on the web site, and **Read what happened** opens it. **Put away** takes the card off Home until the
/// notice changes.
struct ServiceNoticeCard: View {
    let words: ServiceNotice.Words
    let onRead: () -> Void
    let onPutAway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                Icon(.triangleAlert, size: 18)
                    .foregroundStyle(ThroColor.colorStatusWarning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                    Text(words.title)
                        .thro(ThroTypography.label.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(words.summary)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: ThroSpacing.spacing4) {
                ThroButton("Read what happened", variant: .ink, size: .small, action: onRead)
                ThroTextButton("Put away", tone: .quiet, action: onPutAway)
            }
        }
        .padding(ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorStatusWarningSurface)
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium))
        .accessibilityElement(children: .contain)
    }
}
