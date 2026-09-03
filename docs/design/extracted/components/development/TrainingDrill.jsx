try { (() => {
function TrainingDrill({
  name,
  detail,
  length,
  progress,
  total,
  state = 'pending',
  onClick
}) {
  const done = state === 'complete';
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: 'var(--spacing-4) 0',
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: done ? 'circle-check' : state === 'active' ? 'play' : 'circle',
    size: 18,
    color: done ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, length)), detail ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)',
      paddingLeft: 26
    }
  }, detail) : null, progress != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      paddingLeft: 26
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Progress, {
    value: progress,
    max: total || 100,
    valueLabel: `${progress}/${total || 100}`,
    height: 4
  })) : null);
}
Object.assign(__ds_scope, { TrainingDrill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/TrainingDrill.jsx", error: String((e && e.message) || e) }); }
