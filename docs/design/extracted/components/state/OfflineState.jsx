try { (() => {
function OfflineState({
  title = 'Offline',
  message = 'Scoring continues on this device. Changes will sync when connection returns.',
  inline
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "status",
    style: {
      display: 'flex',
      gap: 'var(--spacing-3)',
      alignItems: 'flex-start',
      padding: inline ? 'var(--spacing-2) var(--spacing-4)' : 'var(--spacing-4)',
      background: 'var(--color-status-neutral-surface)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-medium)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "wifi-off",
    size: 18,
    color: "var(--color-status-offline)",
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase',
      color: 'var(--color-text-primary)'
    }
  }, title), !inline ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      lineHeight: '18px',
      color: 'var(--color-text-secondary)',
      maxWidth: '44ch'
    }
  }, message) : null));
}
Object.assign(__ds_scope, { OfflineState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/OfflineState.jsx", error: String((e && e.message) || e) }); }
