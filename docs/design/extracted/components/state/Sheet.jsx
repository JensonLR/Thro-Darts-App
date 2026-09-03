try { (() => {
function Sheet({
  title,
  eyebrow,
  children,
  onClose,
  footer,
  open = true
}) {
  if (!open) return null;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      background: 'var(--color-background-raised)',
      borderTopLeftRadius: 'var(--radius-sheet)',
      borderTopRightRadius: 'var(--radius-sheet)',
      boxShadow: 'var(--elevation-sheet)',
      padding: 'var(--spacing-4) var(--space-screen-gutter) var(--spacing-6)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 4,
      borderRadius: 2,
      background: 'var(--color-border-strong)',
      margin: '0 auto var(--spacing-4)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
      gap: 'var(--spacing-3)',
      paddingBottom: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", null, eyebrow ? /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow"
  }, eyebrow) : null, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '-0.01em',
      color: 'var(--color-text-primary)'
    }
  }, title)), onClose ? /*#__PURE__*/React.createElement(__ds_scope.IconButton, {
    icon: "x",
    label: "Close",
    onClick: onClose
  }) : null), /*#__PURE__*/React.createElement("div", null, children), footer ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 'var(--spacing-5)'
    }
  }, footer) : null);
}
Object.assign(__ds_scope, { Sheet });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/Sheet.jsx", error: String((e && e.message) || e) }); }
