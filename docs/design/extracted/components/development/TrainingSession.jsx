try { (() => {
function TrainingSession({
  title = 'Today',
  duration = '20 min',
  focus,
  drills = [],
  onStart,
  startLabel = 'Start session'
}) {
  return /*#__PURE__*/React.createElement("section", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      justifyContent: 'space-between'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-extrabold)',
      letterSpacing: '-0.01em',
      color: 'var(--color-text-primary)'
    }
  }, title), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, duration)), focus ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-secondary)'
    }
  }, focus) : null, /*#__PURE__*/React.createElement("div", null, drills.map(d => /*#__PURE__*/React.createElement("div", {
    key: d.name,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: 'var(--spacing-3) 0',
      borderTop: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, d.name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, d.length)))), onStart ? /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: onStart
  }, startLabel) : null);
}
Object.assign(__ds_scope, { TrainingSession });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/TrainingSession.jsx", error: String((e && e.message) || e) }); }
