try { (() => {
function EmptyState({
  title,
  message,
  actionLabel,
  onAction
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-8) 0',
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.02em',
      textTransform: 'uppercase',
      color: 'var(--color-text-primary)'
    }
  }, title), message ? /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      lineHeight: '24px',
      color: 'var(--color-text-secondary)',
      maxWidth: '40ch'
    }
  }, message) : null, actionLabel ? /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    onClick: onAction
  }, actionLabel) : null);
}
Object.assign(__ds_scope, { EmptyState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/EmptyState.jsx", error: String((e && e.message) || e) }); }
