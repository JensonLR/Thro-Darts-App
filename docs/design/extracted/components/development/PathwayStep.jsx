try { (() => {
function PathwayStep({
  label,
  rating,
  context,
  state = 'future',
  gap,
  last,
  onClick
}) {
  const current = state === 'current',
    reached = state === 'reached';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      width: 26
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: current ? 18 : 12,
      height: current ? 18 : 12,
      borderRadius: '50%',
      background: reached || current ? 'var(--color-background-brand)' : 'transparent',
      border: `2px solid ${reached || current ? 'var(--color-background-brand)' : 'var(--color-border-strong)'}`
    }
  }), !last ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      width: 2,
      background: reached ? 'var(--color-background-brand)' : 'var(--color-border-default)',
      minHeight: 32
    }
  }) : null), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    disabled: !onClick,
    style: {
      flex: 1,
      textAlign: 'left',
      background: 'none',
      border: 0,
      padding: '0 0 var(--spacing-6)',
      cursor: onClick ? 'pointer' : 'default',
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: current ? 'var(--color-text-primary)' : 'var(--color-text-secondary)'
    }
  }, label), rating ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, rating) : null), context ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      lineHeight: '18px',
      color: 'var(--color-text-secondary)',
      maxWidth: '40ch'
    }
  }, context) : null, gap ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-brand)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "move-right",
    size: 13
  }), gap) : null));
}
Object.assign(__ds_scope, { PathwayStep });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/PathwayStep.jsx", error: String((e && e.message) || e) }); }
