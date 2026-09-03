try { (() => {
function LoadingState({
  lines = 3,
  heroSkeleton,
  label = 'Loading'
}) {
  const bar = (w, h) => ({
    width: w,
    height: h,
    borderRadius: 'var(--radius-small)',
    background: 'var(--color-surface-secondary)'
  });
  return /*#__PURE__*/React.createElement("div", {
    role: "status",
    "aria-label": label,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)'
    }
  }, heroSkeleton ? /*#__PURE__*/React.createElement("div", {
    style: bar('58%', 52)
  }) : null, Array.from({
    length: lines
  }).map((_, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: bar(i % 3 === 2 ? '62%' : '100%', 14)
  })));
}
Object.assign(__ds_scope, { LoadingState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/LoadingState.jsx", error: String((e && e.message) || e) }); }
