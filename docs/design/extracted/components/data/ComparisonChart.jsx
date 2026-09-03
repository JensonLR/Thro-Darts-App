try { (() => {
function ComparisonChart({
  rows = [],
  youLabel = 'You',
  benchmarkLabel = 'Target level'
}) {
  return /*#__PURE__*/React.createElement("figure", {
    style: {
      margin: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 10,
      height: 10,
      background: 'var(--color-chart-primary)'
    }
  }), youLabel), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 10,
      height: 2,
      background: 'var(--color-text-secondary)'
    }
  }), benchmarkLabel)), rows.map(r => {
    const pct = Math.max(2, Math.min(100, r.value / r.max * 100)),
      bpct = Math.min(100, r.benchmark / r.max * 100);
    return /*#__PURE__*/React.createElement("div", {
      key: r.label,
      style: {
        display: 'flex',
        flexDirection: 'column',
        gap: 6
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'baseline'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-label-default-size)',
        fontWeight: 'var(--font-weight-semibold)',
        color: 'var(--color-text-primary)'
      }
    }, r.label), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-sport)',
        fontSize: 'var(--typography-label-default-size)',
        fontVariantNumeric: 'tabular-nums',
        color: 'var(--color-text-secondary)'
      }
    }, r.value, r.unit || '', " ", /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--color-text-tertiary)'
      }
    }, "/ ", r.benchmark, r.unit || ''))), /*#__PURE__*/React.createElement("div", {
      style: {
        position: 'relative',
        height: 10,
        background: 'var(--color-surface-secondary)'
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        position: 'absolute',
        inset: '0 auto 0 0',
        width: pct + '%',
        background: 'var(--color-chart-primary)'
      }
    }), /*#__PURE__*/React.createElement("div", {
      style: {
        position: 'absolute',
        top: -3,
        bottom: -3,
        left: bpct + '%',
        width: 2,
        background: 'var(--color-text-secondary)'
      }
    })));
  }));
}
Object.assign(__ds_scope, { ComparisonChart });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/ComparisonChart.jsx", error: String((e && e.message) || e) }); }
