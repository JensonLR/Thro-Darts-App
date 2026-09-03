try { (() => {
const CLASSES = {
  action: ['bell-ring', 'var(--color-status-live)', 'Action required'],
  information: ['info', 'var(--color-status-info)', 'Information'],
  opportunity: ['compass', 'var(--color-text-brand)', 'Opportunity'],
  social: ['users', 'var(--color-text-secondary)', 'Social'],
  development: ['trending-up', 'var(--color-text-brand)', 'Development'],
  live: ['radio', 'var(--color-status-live)', 'Live'],
  milestone: ['award', 'var(--color-text-achievement)', 'Milestone']
};
function Notification({
  type = 'information',
  title,
  body,
  time,
  unread,
  onClick
}) {
  const [icon, color, label] = CLASSES[type] || CLASSES.information;
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    style: {
      width: '100%',
      display: 'flex',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-4) 0',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 20,
    color: color,
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 3
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)',
      alignItems: 'baseline'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      color
    }
  }, label), time ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-tertiary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, time) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: unread ? 'var(--font-weight-bold)' : 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, title), body ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      lineHeight: '18px',
      color: 'var(--color-text-secondary)'
    }
  }, body) : null), unread ? /*#__PURE__*/React.createElement("span", {
    "aria-label": "Unread",
    style: {
      width: 8,
      height: 8,
      borderRadius: '50%',
      background: 'var(--color-background-brand)',
      marginTop: 8
    }
  }) : null);
}
Object.assign(__ds_scope, { Notification });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/Notification.jsx", error: String((e && e.message) || e) }); }
