try { (() => {
function LiveIndicator({
  label = 'Live',
  pulse = true,
  size = 'medium'
}) {
  const fs = size === 'small' ? 'var(--typography-metadata-size)' : 'var(--typography-label-strong-size)';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      color: 'var(--color-status-live)',
      fontFamily: 'var(--font-ui)',
      fontSize: fs,
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.08em',
      textTransform: 'uppercase'
    }
  }, /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      width: 8,
      height: 8,
      borderRadius: '50%',
      background: 'currentColor',
      animation: pulse ? 'thro-live-pulse 1.6s var(--motion-easing-resolve) infinite' : 'none'
    }
  }), label, /*#__PURE__*/React.createElement("style", null, '@keyframes thro-live-pulse{0%,100%{opacity:1}50%{opacity:0.35}}@media (prefers-reduced-motion:reduce){[style*="thro-live-pulse"]{animation:none!important}}'));
}
Object.assign(__ds_scope, { LiveIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/LiveIndicator.jsx", error: String((e && e.message) || e) }); }
