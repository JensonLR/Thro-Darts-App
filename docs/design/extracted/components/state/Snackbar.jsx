try { (() => {
const TONES = {
  neutral: ['var(--thro-ink)', 'var(--thro-chalk)', 'info'],
  success: ['var(--thro-green)', 'var(--thro-chalk)', 'circle-check'],
  error: ['var(--color-status-error)', 'var(--thro-chalk)', 'triangle-alert'],
  offline: ['var(--thro-pewter-dark)', 'var(--thro-chalk)', 'wifi-off']
};
function Snackbar({
  message,
  tone = 'neutral',
  actionLabel,
  onAction
}) {
  const [bg, fg, icon] = TONES[tone] || TONES.neutral;
  return /*#__PURE__*/React.createElement("div", {
    role: "status",
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-3) var(--spacing-4)',
      background: bg,
      color: fg,
      borderRadius: 'var(--radius-medium)',
      boxShadow: 'var(--elevation-3)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18,
    color: fg
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-medium)'
    }
  }, message), actionLabel ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      border: 0,
      background: 'none',
      cursor: 'pointer',
      color: fg,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase'
    }
  }, actionLabel) : null);
}
Object.assign(__ds_scope, { Snackbar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/Snackbar.jsx", error: String((e && e.message) || e) }); }
