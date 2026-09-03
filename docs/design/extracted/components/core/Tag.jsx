try { (() => {
const TONES = {
  neutral: ['var(--color-status-neutral-surface)', 'var(--color-text-secondary)'],
  brand: ['var(--color-background-brand-subtle)', 'var(--color-text-brand)'],
  success: ['var(--color-status-success-surface)', 'var(--color-status-success)'],
  warning: ['var(--color-status-warning-surface)', 'var(--color-status-warning)'],
  error: ['var(--color-status-error-surface)', 'var(--color-status-error)'],
  info: ['var(--color-status-info-surface)', 'var(--color-status-info)'],
  live: ['var(--color-status-live-surface)', 'var(--color-status-live)'],
  achievement: ['var(--thro-bronze-tint)', 'var(--color-text-achievement)']
};
function Tag({
  children,
  tone = 'neutral',
  icon,
  outlined,
  uppercase = true
}) {
  const [bg, fg] = TONES[tone] || TONES.neutral;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 'var(--spacing-1)',
      background: outlined ? 'transparent' : bg,
      color: fg,
      border: outlined ? `1px solid ${fg}` : '1px solid transparent',
      borderRadius: 'var(--radius-status)',
      padding: '3px 10px',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      lineHeight: '18px',
      fontWeight: 'var(--font-weight-semibold)',
      letterSpacing: uppercase ? '0.06em' : '0',
      textTransform: uppercase ? 'uppercase' : 'none',
      whiteSpace: 'nowrap'
    }
  }, icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 13
  }) : null, children);
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Tag.jsx", error: String((e && e.message) || e) }); }
