try { (() => {
const FIT = {
  good: ['success', 'Good competitive fit'],
  strong: ['info', 'Strong challenge'],
  stretch: ['warning', 'Stretch field']
};
function EventRow({
  name,
  date,
  venue,
  distance,
  format,
  entry,
  fit,
  status,
  onClick
}) {
  const fitDef = fit ? FIT[fit] : null;
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    style: {
      width: '100%',
      display: 'flex',
      gap: 'var(--spacing-4)',
      alignItems: 'flex-start',
      padding: 'var(--spacing-4) 0',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      cursor: 'pointer',
      textAlign: 'left'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      letterSpacing: '0.06em',
      textTransform: 'uppercase',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, date), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      lineHeight: '24px',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '-0.01em',
      color: 'var(--color-text-primary)'
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, [venue, distance, format, entry].filter(Boolean).join(' · ')), fitDef || status ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 6,
      paddingTop: 2
    }
  }, fitDef ? /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: fitDef[0],
    uppercase: false
  }, fitDef[1]) : null, status ? /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: "neutral"
  }, status) : null) : null), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-right",
    size: 18,
    color: "var(--color-text-tertiary)",
    style: {
      marginTop: 22
    }
  }));
}
Object.assign(__ds_scope, { EventRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/EventRow.jsx", error: String((e && e.message) || e) }); }
