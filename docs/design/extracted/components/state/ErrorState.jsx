try { (() => {
function ErrorState({
  title = 'Something went wrong',
  what,
  safe,
  todo,
  actionLabel = 'Try again',
  onAction
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "alert",
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-4)',
      border: '1px solid var(--color-status-error)',
      borderRadius: 'var(--radius-card)',
      background: 'var(--color-status-error-surface)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-2)',
      color: 'var(--color-status-error)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "triangle-alert",
    size: 18
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase'
    }
  }, title)), [['What happened', what], ['What is safe', safe], ['What to do', todo]].filter(x => x[1]).map(([l, v]) => /*#__PURE__*/React.createElement("span", {
    key: l,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, l), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-primary)'
    }
  }, v))), onAction ? /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "secondary",
    onClick: onAction
  }, actionLabel) : null);
}
Object.assign(__ds_scope, { ErrorState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/ErrorState.jsx", error: String((e && e.message) || e) }); }
