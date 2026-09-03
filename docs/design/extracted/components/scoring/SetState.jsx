try { (() => {
function SetState({
  home = 1,
  away = 1,
  legs = [[3, 2], [1, 3], [2, 1]],
  theme = 'dark'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-2)',
      fontFamily: 'var(--font-sport)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Sets"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, home, "\u2013", away)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)'
    }
  }, legs.map((l, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      padding: '2px 8px',
      borderRadius: 'var(--radius-small)',
      border: '1px solid var(--color-border-default)',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, l[0], "\u2013", l[1]))));
}
Object.assign(__ds_scope, { SetState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/SetState.jsx", error: String((e && e.message) || e) }); }
