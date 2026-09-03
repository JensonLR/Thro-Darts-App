try { (() => {
function Insight({
  eyebrow = 'Your biggest opportunity',
  headline,
  evidence,
  actionTitle,
  actionLabel,
  onAction,
  tone = 'brand'
}) {
  return /*#__PURE__*/React.createElement("section", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-5)',
      background: tone === 'brand' ? 'var(--color-background-brand-subtle)' : 'var(--color-status-neutral-surface)',
      borderRadius: 'var(--radius-card)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      color: tone === 'brand' ? 'var(--color-text-brand)' : 'var(--color-text-secondary)'
    }
  }, eyebrow), /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-2-size)',
      lineHeight: 'var(--typography-heading-2-line)',
      fontWeight: 'var(--font-weight-extrabold)',
      letterSpacing: '-0.01em',
      color: 'var(--color-text-primary)'
    }
  }, headline), evidence ? /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      lineHeight: '24px',
      color: 'var(--color-text-secondary)',
      textWrap: 'pretty'
    }
  }, evidence) : null, actionTitle ? /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--color-border-default)',
      paddingTop: 'var(--spacing-3)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Next action"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-large-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, actionTitle), actionLabel ? /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    size: "small",
    onClick: onAction
  }, actionLabel) : null) : null);
}
Object.assign(__ds_scope, { Insight });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/Insight.jsx", error: String((e && e.message) || e) }); }
