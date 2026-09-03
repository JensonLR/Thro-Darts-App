try { (() => {
function Dialog({
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive,
  onConfirm,
  onCancel,
  open = true
}) {
  if (!open) return null;
  return /*#__PURE__*/React.createElement("div", {
    role: "dialog",
    "aria-modal": "true",
    "aria-label": title,
    style: {
      maxWidth: 340,
      background: 'var(--color-background-raised)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-card)',
      padding: 'var(--spacing-6)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)',
      boxShadow: 'var(--elevation-3)'
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, title), message ? /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      lineHeight: '23px',
      color: 'var(--color-text-secondary)'
    }
  }, message) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)',
      paddingTop: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "ghost",
    size: "small",
    onClick: onCancel,
    fullWidth: true
  }, cancelLabel), /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: destructive ? 'destructive' : 'primary',
    size: "small",
    onClick: onConfirm,
    fullWidth: true
  }, confirmLabel)));
}
Object.assign(__ds_scope, { Dialog });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/Dialog.jsx", error: String((e && e.message) || e) }); }
