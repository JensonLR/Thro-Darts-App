try { (() => {
function Confidence({
  level = 'high',
  matches,
  required = 10,
  explain = true
}) {
  const pct = matches != null ? Math.min(100, Math.round(matches / required * 100)) : level === 'high' ? 100 : level === 'medium' ? 66 : 33;
  const words = {
    high: 'High confidence',
    medium: 'Building confidence',
    low: 'Still learning your level'
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'baseline'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Confidence"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-primary)'
    }
  }, words[level])), /*#__PURE__*/React.createElement("div", {
    role: "img",
    "aria-label": `${words[level]}${matches != null ? `, ${matches} of ${required} qualifying matches` : ''}`,
    style: {
      display: 'flex',
      gap: 3,
      height: 6
    }
  }, Array.from({
    length: 10
  }).map((_, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      flex: 1,
      borderRadius: 1,
      background: i < Math.round(pct / 10) ? 'var(--color-background-brand)' : 'var(--color-surface-secondary)'
    }
  }))), explain && matches != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, matches, " of ", required, " qualifying matches complete") : null);
}
Object.assign(__ds_scope, { Confidence });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/Confidence.jsx", error: String((e && e.message) || e) }); }
