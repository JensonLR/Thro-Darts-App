try { (() => {
const QUICK = [180, 140, 100, 60, 45, 26];
function ScoreKeypad({
  onScore,
  onUndo,
  onMiss,
  value = '',
  onDigit,
  theme = 'dark',
  disabled
}) {
  const key = {
    minHeight: 'var(--touch-target-scoring)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'var(--color-surface-primary)',
    border: '1px solid var(--color-border-default)',
    borderRadius: 'var(--radius-keypad)',
    fontFamily: 'var(--font-sport)',
    fontSize: 'var(--typography-heading-2-size)',
    fontWeight: 'var(--font-weight-semibold)',
    fontVariantNumeric: 'tabular-nums',
    color: 'var(--color-text-primary)',
    cursor: 'pointer'
  };
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)',
      padding: 'var(--spacing-4) var(--space-screen-gutter)',
      background: 'var(--color-background-primary)',
      opacity: disabled ? 0.4 : 1,
      pointerEvents: disabled ? 'none' : 'auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(6,1fr)',
      gap: 'var(--spacing-2)'
    }
  }, QUICK.map(q => /*#__PURE__*/React.createElement("button", {
    key: q,
    type: "button",
    onClick: () => onScore && onScore(q),
    style: {
      ...key,
      minHeight: 44,
      fontSize: 'var(--typography-label-default-size)',
      background: 'var(--color-surface-secondary)'
    }
  }, q))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(3,1fr)',
      gap: 'var(--spacing-2)'
    }
  }, [1, 2, 3, 4, 5, 6, 7, 8, 9].map(d => /*#__PURE__*/React.createElement("button", {
    key: d,
    type: "button",
    onClick: () => onDigit && onDigit(String(d)),
    style: key
  }, d)), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onMiss,
    style: {
      ...key,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase'
    }
  }, "Miss"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => onDigit && onDigit('0'),
    style: key
  }, "0"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Undo last score",
    onClick: onUndo,
    style: {
      ...key,
      background: 'var(--color-surface-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "undo-2",
    size: 24
  }))), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => onScore && onScore(Number(value || 0)),
    style: {
      minHeight: 'var(--touch-target-scoring)',
      border: 0,
      borderRadius: 'var(--radius-keypad)',
      background: 'var(--color-surface-brand)',
      color: 'var(--thro-chalk)',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-large-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase',
      cursor: 'pointer'
    }
  }, value ? `Enter ${value}` : 'Enter score'));
}
Object.assign(__ds_scope, { ScoreKeypad });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/ScoreKeypad.jsx", error: String((e && e.message) || e) }); }
