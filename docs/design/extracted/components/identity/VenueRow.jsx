try { (() => {
function VenueRow({
  name,
  town,
  boards,
  distance,
  tonight,
  accessible,
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
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, name, accessible ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "accessibility",
    size: 14,
    color: "var(--color-text-secondary)",
    title: "Step-free access"
  }) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, [town, boards != null ? `${boards} boards` : null, distance].filter(Boolean).join(' · '))), tonight ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-brand)'
    }
  }, "Tonight") : null, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  }));
}
Object.assign(__ds_scope, { VenueRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/VenueRow.jsx", error: String((e && e.message) || e) }); }
