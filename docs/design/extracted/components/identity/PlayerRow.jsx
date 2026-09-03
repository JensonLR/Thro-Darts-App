try { (() => {
function PlayerRow({
  name,
  rating,
  team,
  rank,
  delta,
  verified,
  meta,
  onClick
}) {
  const up = (delta || 0) > 0;
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
  }, rank != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 34,
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, rank) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.PlayerIdentity, {
    name: name,
    rating: rating,
    team: team,
    verified: verified,
    size: "small"
  })), meta ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, meta) : null, delta != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 2,
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: up ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: up ? 'arrow-up' : 'arrow-down',
    size: 12
  }), Math.abs(delta)) : null, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  }));
}
Object.assign(__ds_scope, { PlayerRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/PlayerRow.jsx", error: String((e && e.message) || e) }); }
