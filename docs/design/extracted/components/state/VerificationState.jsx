try { (() => {
const MAP = {
  'self-reported': ['file-pen', 'neutral', 'Self-reported', 'Entered by a player. Not independently confirmed.'],
  'participant-confirmed': ['users', 'info', 'Participant-confirmed', 'Both players confirmed this result.'],
  'thro-recorded': ['smartphone', 'info', 'THRØ recorded', 'Scored live in the THRØ app.'],
  'organiser-confirmed': ['clipboard-check', 'success', 'Organiser-confirmed', 'Confirmed by the competition organiser.'],
  'thro-verified': ['circle-check', 'success', 'THRØ verified', 'Recorded in THRØ and confirmed by the organiser.'],
  pending: ['clock', 'warning', 'Pending', 'Awaiting confirmation.'],
  disputed: ['triangle-alert', 'error', 'Disputed', 'A participant has raised a dispute. Under review.'],
  corrected: ['rotate-ccw', 'info', 'Corrected', 'This result was amended after submission.']
};
const TONE = {
  neutral: 'var(--color-text-secondary)',
  info: 'var(--color-status-info)',
  success: 'var(--color-status-verified)',
  warning: 'var(--color-status-pending)',
  error: 'var(--color-status-disputed)'
};
function VerificationState({
  state = 'thro-verified',
  explain,
  compact
}) {
  const [icon, tone, label, help] = MAP[state] || MAP['self-reported'];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)',
      alignItems: compact ? 'center' : 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: compact ? 14 : 18,
    color: TONE[tone],
    style: {
      marginTop: compact ? 0 : 2
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: compact ? 'var(--typography-metadata-size)' : 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: TONE[tone]
    }
  }, label), explain && !compact ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      maxWidth: '42ch'
    }
  }, help) : null));
}
Object.assign(__ds_scope, { VerificationState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/VerificationState.jsx", error: String((e && e.message) || e) }); }
