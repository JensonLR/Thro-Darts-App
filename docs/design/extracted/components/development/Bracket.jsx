try { (() => {
function Bracket({
  rounds = [],
  highlightPlayer,
  onSelectMatch,
  selectedId
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-4)',
      overflowX: 'auto',
      paddingBottom: 'var(--spacing-3)'
    }
  }, rounds.map(r => /*#__PURE__*/React.createElement("div", {
    key: r.name,
    style: {
      minWidth: 196,
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, r.name), r.matches.map(m => {
    const mine = highlightPlayer && [m.home, m.away].includes(highlightPlayer),
      sel = selectedId === m.id;
    return /*#__PURE__*/React.createElement("button", {
      key: m.id,
      type: "button",
      onClick: () => onSelectMatch && onSelectMatch(m.id),
      "aria-current": sel ? 'true' : undefined,
      style: {
        textAlign: 'left',
        cursor: 'pointer',
        padding: 'var(--spacing-3)',
        borderRadius: 'var(--radius-medium)',
        background: mine ? 'var(--color-background-brand-subtle)' : 'var(--color-surface-primary)',
        border: `${sel ? 2 : 1}px solid ${sel ? 'var(--color-border-focus)' : mine ? 'var(--color-border-brand)' : 'var(--color-border-default)'}`,
        display: 'flex',
        flexDirection: 'column',
        gap: 6
      }
    }, [[m.home, m.homeScore], [m.away, m.awayScore]].map(([p, s], i) => /*#__PURE__*/React.createElement("span", {
      key: i,
      style: {
        display: 'flex',
        minWidth: 0,
        justifyContent: 'space-between',
        gap: 'var(--spacing-2)'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        minWidth: 0,
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-label-strong-size)',
        fontWeight: p === highlightPlayer ? 'var(--font-weight-bold)' : 'var(--font-weight-medium)',
        color: 'var(--color-text-primary)',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis'
      }
    }, p || 'TBC'), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-sport)',
        fontSize: 'var(--typography-label-strong-size)',
        fontWeight: 'var(--font-weight-bold)',
        fontVariantNumeric: 'tabular-nums',
        color: s != null ? 'var(--color-text-primary)' : 'var(--color-text-tertiary)'
      }
    }, s != null ? s : '–'))), m.state === 'live' ? /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: '11px',
        fontWeight: 'var(--font-weight-bold)',
        letterSpacing: '0.08em',
        textTransform: 'uppercase',
        color: 'var(--color-status-live)'
      }
    }, "Live \xB7 Board ", m.board) : null);
  }))));
}
Object.assign(__ds_scope, { Bracket });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/Bracket.jsx", error: String((e && e.message) || e) }); }
