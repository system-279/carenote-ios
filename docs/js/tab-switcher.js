// CareNote Architecture Docs - Audience Tab Switcher

document.addEventListener('DOMContentLoaded', () => {
  const saved = localStorage.getItem('carenote-audience') || 'general';
  setAudience(saved);

  document.querySelectorAll('.audience-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      setAudience(btn.dataset.tab);
    });
  });
});

function setAudience(audience) {
  document.body.classList.remove('audience-engineer', 'audience-general');
  document.body.classList.add('audience-' + audience);
  localStorage.setItem('carenote-audience', audience);

  document.querySelectorAll('.audience-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === audience);
  });

  // Re-render Mermaid diagrams that became visible after tab switch
  if (typeof mermaid !== 'undefined') {
    setTimeout(() => { mermaid.run(); }, 100);
  }
}
