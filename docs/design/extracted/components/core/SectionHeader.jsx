try { (() => {
function SectionHeader({
  title,
  action,
  onAction,
  meta
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      justifyContent: 'space-between',
      gap: 'var(--spacing-3)',
      paddingBottom: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-eyebrow-size)',
      lineHeight: 'var(--typography-eyebrow-line)',
      letterSpacing: 'var(--typography-eyebrow-tracking)',
      textTransform: 'uppercase',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-secondary)'
    }
  }, title), meta ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-tertiary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, meta) : null), action ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      background: 'none',
      border: 0,
      padding: 0,
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      color: 'var(--color-text-brand)',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      cursor: 'pointer'
    }
  }, action, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-right",
    size: 14
  })) : null);
}
Object.assign(__ds_scope, { SectionHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/SectionHeader.jsx", error: String((e && e.message) || e) }); }
