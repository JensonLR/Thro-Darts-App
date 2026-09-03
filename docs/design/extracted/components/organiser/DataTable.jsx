try { (() => {
function DataTable({
  columns = [],
  rows = [],
  caption,
  onRowClick,
  selectedId,
  dense
}) {
  const pad = dense ? '8px var(--spacing-3)' : 'var(--spacing-3)';
  // Nowrap tabular cells make the table's min-content wider than its container in
  // narrow layouts. A percentage table width is a floor, not a cap, so the table is
  // wrapped in a scroll container: figures stay aligned and nothing escapes the column.
  return /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0,
      maxWidth: '100%',
      overflowX: 'auto'
    }
  }, /*#__PURE__*/React.createElement("table", {
    style: {
      width: '100%',
      borderCollapse: 'collapse',
      fontFamily: 'var(--font-ui)'
    }
  }, caption ? /*#__PURE__*/React.createElement("caption", {
    style: {
      captionSide: 'top',
      textAlign: 'left',
      paddingBottom: 'var(--spacing-3)'
    },
    className: "thro-eyebrow"
  }, caption) : null, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, columns.map(c => /*#__PURE__*/React.createElement("th", {
    key: c.key,
    scope: "col",
    style: {
      textAlign: c.numeric ? 'right' : 'left',
      padding: pad,
      borderBottom: '1px solid var(--color-border-strong)',
      fontSize: 'var(--typography-eyebrow-size)',
      lineHeight: 'var(--typography-eyebrow-line)',
      letterSpacing: 'var(--typography-eyebrow-tracking)',
      textTransform: 'uppercase',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-secondary)',
      whiteSpace: 'nowrap',
      width: c.width
    }
  }, c.label)))), /*#__PURE__*/React.createElement("tbody", null, rows.map(r => {
    const sel = selectedId === r.id;
    return /*#__PURE__*/React.createElement("tr", {
      key: r.id,
      onClick: onRowClick ? () => onRowClick(r.id) : undefined,
      "aria-current": sel ? 'true' : undefined,
      style: {
        cursor: onRowClick ? 'pointer' : 'default',
        background: sel ? 'var(--color-background-brand-subtle)' : 'transparent'
      }
    }, columns.map(c => /*#__PURE__*/React.createElement("td", {
      key: c.key,
      style: {
        textAlign: c.numeric ? 'right' : 'left',
        padding: pad,
        borderBottom: '1px solid var(--color-border-default)',
        fontFamily: c.numeric ? 'var(--font-sport)' : 'var(--font-ui)',
        fontVariantNumeric: c.numeric ? 'tabular-nums' : 'normal',
        fontSize: 'var(--typography-label-default-size)',
        fontWeight: c.strong ? 'var(--font-weight-bold)' : 'var(--font-weight-regular)',
        color: 'var(--color-text-primary)',
        whiteSpace: c.wrap ? 'normal' : 'nowrap'
      }
    }, r[c.key])));
  }))));
}
Object.assign(__ds_scope, { DataTable });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/organiser/DataTable.jsx", error: String((e && e.message) || e) }); }
