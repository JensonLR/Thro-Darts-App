try { (() => {
function TeamRow({
  name,
  venue,
  division,
  played,
  points,
  position,
  onClick
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    style: {
      width: '100%',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-3) 0',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      cursor: 'pointer',
      textAlign: 'left'
    }
  }, position != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 28,
      fontFamily: 'var(--font-sport)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, position) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, [venue, division].filter(Boolean).join(' · '))), played != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, played, " P") : null, points != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 32,
      textAlign: 'right',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, points) : null, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  }));
}
Object.assign(__ds_scope, { TeamRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/TeamRow.jsx", error: String((e && e.message) || e) }); }
