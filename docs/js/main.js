// CareNote Architecture Docs - Main JS

document.addEventListener('DOMContentLoaded', () => {
  // Highlight active nav link
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-link').forEach(link => {
    const href = link.getAttribute('href');
    if (href === currentPage || (currentPage === '' && href === 'index.html')) {
      link.classList.add('active');
    }
  });

  // Initialize Mermaid
  if (typeof mermaid !== 'undefined') {
    mermaid.initialize({
      startOnLoad: true,
      theme: 'base',
      themeVariables: {
        primaryColor: '#DBEAFE',
        primaryTextColor: '#1E40AF',
        primaryBorderColor: '#93C5FD',
        lineColor: '#64748B',
        secondaryColor: '#ECFDF5',
        secondaryTextColor: '#065F46',
        secondaryBorderColor: '#6EE7B7',
        tertiaryColor: '#F3E8FF',
        tertiaryTextColor: '#6B21A8',
        tertiaryBorderColor: '#C4B5FD',
        noteBkgColor: '#FFFBEB',
        noteTextColor: '#92400E',
        noteBorderColor: '#FDE68A',
        fontFamily: '"Noto Sans JP", sans-serif',
        fontSize: '14px'
      },
      flowchart: { curve: 'basis', padding: 20 },
      sequence: { mirrorActors: false, messageMargin: 40 }
    });
  }

  // Accordion
  document.querySelectorAll('.accordion-header').forEach(header => {
    header.addEventListener('click', () => {
      const item = header.parentElement;
      item.classList.toggle('open');
    });
  });
});
