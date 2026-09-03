try { (() => {
function TrendChart({
  points = [1780, 1795, 1788, 1810, 1824, 1821, 1847],
  label = 'Rating',
  reference,
  height = 120,
  tableLabel
}) {
  const min = Math.min(...points, reference ?? Infinity),
    max = Math.max(...points, reference ?? -Infinity);
  const span = max - min || 1,
    w = 100,
    step = points.length > 1 ? w / (points.length - 1) : 0;
  const xy = points.map((p, i) => [i * step, 100 - (p - min) / span * 100]);
  const line = xy.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`).join(' ');
  const refY = reference != null ? 100 - (reference - min) / span * 100 : null;
  return /*#__PURE__*/React.createElement("figure", {
    style: {
      margin: 0,
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
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, points[points.length - 1].toLocaleString('en-GB'))), /*#__PURE__*/React.createElement("svg", {
    viewBox: "0 0 100 100",
    preserveAspectRatio: "none",
    role: "img",
    "aria-label": tableLabel || `${label} trend from ${points[0]} to ${points[points.length - 1]}`,
    style: {
      width: '100%',
      height,
      display: 'block'
    }
  }, refY != null ? /*#__PURE__*/React.createElement("line", {
    x1: "0",
    y1: refY,
    x2: "100",
    y2: refY,
    stroke: "var(--color-chart-reference)",
    strokeWidth: "1",
    strokeDasharray: "3 3",
    vectorEffect: "non-scaling-stroke"
  }) : null, /*#__PURE__*/React.createElement("path", {
    d: line,
    fill: "none",
    stroke: "var(--color-chart-primary)",
    strokeWidth: "2",
    strokeLinejoin: "round",
    strokeLinecap: "round",
    vectorEffect: "non-scaling-stroke"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: xy[xy.length - 1][0],
    cy: xy[xy.length - 1][1],
    r: "3",
    fill: "var(--color-chart-primary)",
    vectorEffect: "non-scaling-stroke"
  })), /*#__PURE__*/React.createElement("figcaption", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, points.length, " rated matches", reference != null ? ` · benchmark ${reference.toLocaleString('en-GB')}` : ''));
}
Object.assign(__ds_scope, { TrendChart });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/TrendChart.jsx", error: String((e && e.message) || e) }); }
