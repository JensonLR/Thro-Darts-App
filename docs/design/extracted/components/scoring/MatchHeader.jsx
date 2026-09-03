try { (() => {
function MatchHeader({
  competition,
  round,
  board,
  format,
  theme = 'dark'
}) {
  const cell = {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
    minWidth: 0
  };
  const val = {
    fontFamily: 'var(--font-ui)',
    fontSize: 'var(--typography-label-default-size)',
    fontWeight: 'var(--font-weight-bold)',
    color: 'var(--color-text-primary)',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis'
  };
  const num = {
    ...val,
    fontFamily: 'var(--font-sport)',
    fontVariantNumeric: 'tabular-nums'
  };
  return /*#__PURE__*/React.createElement("header", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      gap: 'var(--spacing-4)',
      padding: 'var(--spacing-3) var(--space-screen-gutter)',
      background: 'var(--color-background-primary)',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      ...cell,
      flex: '1 1 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Competition"), /*#__PURE__*/React.createElement("span", {
    style: val
  }, competition)), round ? /*#__PURE__*/React.createElement("span", {
    style: {
      ...cell,
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Round"), /*#__PURE__*/React.createElement("span", {
    style: val
  }, round)) : null, board ? /*#__PURE__*/React.createElement("span", {
    style: {
      ...cell,
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Board"), /*#__PURE__*/React.createElement("span", {
    style: num
  }, board)) : null, format ? /*#__PURE__*/React.createElement("span", {
    style: {
      ...cell,
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Format"), /*#__PURE__*/React.createElement("span", {
    style: num
  }, format)) : null);
}
Object.assign(__ds_scope, { MatchHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/MatchHeader.jsx", error: String((e && e.message) || e) }); }
