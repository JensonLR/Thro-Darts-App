try { (() => {
// Lucide (MIT) is the approved THRØ glyph set, inlined from assets/icons/ so glyphs
// render offline and inherit a token colour. 24x24 grid, 2px stroke, round caps.
function Icon({
  name = 'target',
  size = 20,
  color = 'currentColor',
  title,
  style
}) {
  const inner = __ds_scope.iconPaths[name] || __ds_scope.iconPaths.circle;
  return /*#__PURE__*/React.createElement("svg", {
    viewBox: "0 0 24 24",
    width: size,
    height: size,
    fill: "none",
    stroke: color,
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round",
    role: title ? 'img' : 'presentation',
    "aria-label": title,
    "aria-hidden": title ? undefined : true,
    focusable: "false",
    style: {
      display: 'inline-block',
      flex: '0 0 auto',
      verticalAlign: 'middle',
      ...style
    },
    dangerouslySetInnerHTML: {
      __html: inner
    }
  });
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Icon.jsx", error: String((e && e.message) || e) }); }
