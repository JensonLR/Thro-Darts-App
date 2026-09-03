try { (() => {
function CallControl({
  round,
  home,
  away,
  board,
  waiting,
  onCall,
  onReassign,
  onWithdraw,
  called
}) {
  const [menu, setMenu] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)',
      minWidth: 0,
      padding: 'var(--spacing-4)',
      background: 'var(--color-background-raised)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-card)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      justifyContent: 'space-between',
      gap: 'var(--spacing-3)',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      minWidth: 0,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, round), waiting ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-status-pending)'
    }
  }, "Waiting ", waiting) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 'var(--spacing-3)',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      flex: '1 1 auto',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, home, " v ", away), board ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      display: 'flex',
      alignItems: 'baseline',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Board"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      lineHeight: 1,
      color: 'var(--color-text-primary)'
    }
  }, board)) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-2)',
      minWidth: 0
    }
  }, called ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-status-live)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "bell-ring",
    size: 16
  }), "Called") : /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    size: "small",
    onClick: onCall
  }, "Call to board"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), onReassign || onWithdraw ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'relative',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.IconButton, {
    icon: "ellipsis",
    label: "More actions",
    size: 44,
    variant: "outlined",
    onClick: () => setMenu(m => !m)
  }), menu ? /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      right: 0,
      bottom: 48,
      zIndex: 2,
      minWidth: 180,
      display: 'flex',
      flexDirection: 'column',
      background: 'var(--color-background-raised)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-medium)',
      boxShadow: 'var(--elevation-3)',
      overflow: 'hidden'
    }
  }, onReassign ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => {
      setMenu(false);
      onReassign();
    },
    style: {
      textAlign: 'left',
      border: 0,
      background: 'none',
      padding: '12px 16px',
      minHeight: 44,
      cursor: 'pointer',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap'
    }
  }, "Reassign board") : null, onWithdraw ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => {
      setMenu(false);
      onWithdraw();
    },
    style: {
      textAlign: 'left',
      border: 0,
      background: 'none',
      padding: '12px 16px',
      minHeight: 44,
      cursor: 'pointer',
      borderTop: '1px solid var(--color-border-default)',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-status-error)',
      whiteSpace: 'nowrap'
    }
  }, "Withdraw a player") : null) : null) : null));
}
Object.assign(__ds_scope, { CallControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/organiser/CallControl.jsx", error: String((e && e.message) || e) }); }
