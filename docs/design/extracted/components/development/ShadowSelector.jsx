try { (() => {
const MODES = [{
  id: 'current',
  label: 'Current You',
  detail: 'Your live statistical model'
}, {
  id: 'season',
  label: 'Season You',
  detail: 'This season, all rated matches'
}, {
  id: 'peak',
  label: 'Peak You',
  detail: 'Your best sustained run'
}, {
  id: 'pressure',
  label: 'Pressure You',
  detail: 'Deciding legs only'
}, {
  id: 'next',
  label: 'Next Level',
  detail: 'Your target competitive level'
}];
function ShadowSelector({
  value = 'current',
  onChange,
  theme = 'dark'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    role: "radiogroup",
    "aria-label": "Shadow model",
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, MODES.map(m => {
    const on = value === m.id;
    return /*#__PURE__*/React.createElement("button", {
      key: m.id,
      type: "button",
      role: "radio",
      "aria-checked": on,
      onClick: () => onChange && onChange(m.id),
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--spacing-3)',
        padding: 'var(--spacing-4)',
        cursor: 'pointer',
        textAlign: 'left',
        background: on ? 'var(--color-background-brand-subtle)' : 'transparent',
        border: `1px solid ${on ? 'var(--color-border-brand)' : 'var(--color-border-default)'}`,
        borderRadius: 'var(--radius-card)'
      }
    }, /*#__PURE__*/React.createElement("span", {
      "aria-hidden": "true",
      style: {
        width: 26,
        height: 26,
        flex: '0 0 auto',
        borderRadius: '50%',
        border: `2px solid ${on ? 'var(--color-text-brand)' : 'var(--color-border-strong)'}`,
        position: 'relative',
        overflow: 'hidden'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        top: '50%',
        left: -4,
        right: -4,
        height: 2,
        background: on ? 'var(--color-text-brand)' : 'var(--color-border-strong)',
        transform: 'rotate(-45deg)'
      }
    })), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        gap: 2
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-body-default-size)',
        fontWeight: 'var(--font-weight-bold)',
        color: 'var(--color-text-primary)'
      }
    }, m.label), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-metadata-size)',
        color: 'var(--color-text-secondary)'
      }
    }, m.detail)));
  }));
}
Object.assign(__ds_scope, { ShadowSelector });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/development/ShadowSelector.jsx", error: String((e && e.message) || e) }); }
