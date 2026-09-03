try { (() => {
const MAP = {
  syncing: ['refresh-cw', 'var(--color-status-info)', 'Syncing', 'Sending this match to THRØ.'],
  synced: ['cloud-check', 'var(--color-status-success)', 'Synced', 'This match is saved to THRØ.'],
  queued: ['clock', 'var(--color-status-pending)', 'Queued', 'Will sync when connection returns.'],
  failed: ['cloud-off', 'var(--color-status-error)', 'Not synced', 'Scoring is safe on this device. Retry when you have signal.']
};
function SyncState({
  state = 'synced',
  detail,
  onRetry
}) {
  const [icon, color, label, help] = MAP[state] || MAP.synced;
  return /*#__PURE__*/React.createElement("div", {
    role: "status",
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-3) var(--spacing-4)',
      background: 'var(--color-status-neutral-surface)',
      borderRadius: 'var(--radius-medium)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18,
    color: color
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, detail || help)), state === 'failed' && onRetry ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onRetry,
    style: {
      border: 0,
      background: 'none',
      cursor: 'pointer',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-brand)'
    }
  }, "Retry") : null);
}
Object.assign(__ds_scope, { SyncState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/SyncState.jsx", error: String((e && e.message) || e) }); }
