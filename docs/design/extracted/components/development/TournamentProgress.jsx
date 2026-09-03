try { (() => {
function TournamentProgress({
  rounds = [],
  nextLabel
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 0
    }
  }, rounds.map((r, i) => {
    const st = r.state || 'future';
    return /*#__PURE__*/React.createElement("div", {
      key: r.round,
      style: {
        display: 'flex',
        gap: 'var(--spacing-3)',
        alignItems: 'center',
        padding: 'var(--spacing-3) 0',
        borderBottom: i < rounds.length - 1 ? '1px solid var(--color-border-default)' : 'none'
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: st === 'won' ? 'circle-check' : st === 'lost' ? 'circle-x' : st === 'active' ? 'circle-dot' : 'circle',
      size: 18,
      color: st === 'won' ? 'var(--color-status-success)' : st === 'lost' ? 'var(--color-status-error)' : st === 'active' ? 'var(--color-status-live)' : 'var(--color-text-tertiary)'
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        minWidth: 0,
        display: 'flex',
        flexDirection: 'column'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-label-default-size)',
        fontWeight: 'var(--font-weight-bold)',
        color: st === 'future' ? 'var(--color-text-secondary)' : 'var(--color-text-primary)'
      }
    }, r.round), r.opponent ? /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-metadata-size)',
        color: 'var(--color-text-secondary)'
      }
    }, r.opponent) : null), r.score ? /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-sport)',
        fontSize: 'var(--typography-heading-3-size)',
        fontWeight: 'var(--font-weight-bold)',
        fontVariantNumeric: 'tabular-nums',
        color: 'var(--color-text-primary)'
      }
    }, r.score) : null);
  }), nextLabel ? /*#__PURE__*/React.createElement("span", {
    style: {
      paddingTop: 'var(--spacing-4)',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-brand)'
    }
  }, nextLabel) : null);
}
Object.assign(__ds_scope, { TournamentProgress });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/TournamentProgress.jsx", error: String((e && e.message) || e) }); }
