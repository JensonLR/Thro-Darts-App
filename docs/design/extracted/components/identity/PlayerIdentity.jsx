try { (() => {
const SZ = {
  small: {
    n: 'var(--typography-label-default-size)',
    m: 32
  },
  medium: {
    n: 'var(--typography-heading-3-size)',
    m: 40
  },
  large: {
    n: 'var(--typography-heading-2-size)',
    m: 52
  }
};
function PlayerIdentity({
  name,
  initials,
  rating,
  team,
  region,
  verified,
  size = 'medium',
  align = 'left'
}) {
  const s = SZ[size] || SZ.medium;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      minWidth: 0,
      alignItems: 'center',
      gap: 'var(--spacing-3)',
      flexDirection: align === 'right' ? 'row-reverse' : 'row',
      textAlign: align
    }
  }, /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      width: s.m,
      height: s.m,
      flex: '0 0 auto',
      borderRadius: '50%',
      border: '1px solid var(--color-border-strong)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-sport)',
      fontWeight: 'var(--font-weight-bold)',
      fontSize: s.m * 0.38,
      color: 'var(--color-text-secondary)',
      background: 'var(--color-surface-secondary)'
    }
  }, initials || (name || '').split(' ').map(w => w[0]).slice(0, 2).join('')), /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      flex: '1 1 0'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      minWidth: 0,
      alignItems: 'center',
      gap: 6,
      justifyContent: align === 'right' ? 'flex-end' : 'flex-start'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      fontFamily: 'var(--font-ui)',
      fontSize: s.n,
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '-0.005em',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, name), verified ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "circle-check",
    size: 14,
    color: "var(--color-status-verified)",
    title: "THR\xD8 verified"
  }) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      minWidth: 0,
      flexWrap: 'wrap',
      gap: 8,
      justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, rating != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, rating.toLocaleString('en-GB')) : null, team ? /*#__PURE__*/React.createElement("span", null, team) : null, region ? /*#__PURE__*/React.createElement("span", null, region) : null)));
}
Object.assign(__ds_scope, { PlayerIdentity });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/PlayerIdentity.jsx", error: String((e && e.message) || e) }); }
