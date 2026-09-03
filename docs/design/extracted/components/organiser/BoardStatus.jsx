try { (() => {
const STATES = {
  free: ['circle', 'var(--color-text-tertiary)', 'Free', 'var(--color-surface-secondary)'],
  called: ['bell-ring', 'var(--color-status-live)', 'Called', 'var(--color-status-live-surface)'],
  playing: ['radio', 'var(--color-status-live)', 'In play', 'var(--color-status-live-surface)'],
  awaiting: ['clock', 'var(--color-status-pending)', 'Awaiting result', 'var(--color-status-warning-surface)'],
  disputed: ['triangle-alert', 'var(--color-status-disputed)', 'Disputed', 'var(--color-status-error-surface)'],
  closed: ['circle-x', 'var(--color-text-tertiary)', 'Closed', 'var(--color-surface-secondary)']
};
function BoardStatus({
  board,
  state = 'free',
  round,
  home,
  away,
  score,
  elapsed,
  selected,
  onClick
}) {
  const [icon, color, label, bg] = STATES[state] || STATES.free;
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    "aria-current": selected ? 'true' : undefined,
    style: {
      textAlign: 'left',
      cursor: 'pointer',
      padding: 'var(--spacing-3)',
      minHeight: 118,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)',
      background: state === 'free' || state === 'closed' ? 'var(--color-background-raised)' : bg,
      borderRadius: 'var(--radius-card)',
      border: `${selected ? 2 : 1}px solid ${selected ? 'var(--color-border-focus)' : 'var(--color-border-default)'}`
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Board"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      lineHeight: 1,
      color: 'var(--color-text-primary)'
    }
  }, board)), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 16,
    color: color,
    title: label
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.06em',
      textTransform: 'uppercase',
      color
    }
  }, label), home ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      gap: 2,
      minWidth: 0
    }
  }, round ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, round) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      gap: 'var(--spacing-2)',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 0,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, home, " v ", away), score ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, score) : null), elapsed ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, elapsed) : null) : /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }));
}
Object.assign(__ds_scope, { BoardStatus });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/organiser/BoardStatus.jsx", error: String((e && e.message) || e) }); }
