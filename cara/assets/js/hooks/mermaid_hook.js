import mermaid from 'mermaid'

// Initialize Mermaid once
mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'loose',
})

function renderAll() {
  setTimeout(() => {
    const unprocessed = document.querySelectorAll('.mermaid:not([data-processed])');
    const actuallyUnprocessed = Array.from(unprocessed).filter(el => {
      const text = el.textContent || "";
      const hasText = text.trim().length > 0;
      
      if (!hasText) return false;
      
      const isAlreadyRendered = el.querySelector('svg') || el.classList.contains('mermaid-rendered');
      if (isAlreadyRendered) return false;

      return true;
    });

    if (actuallyUnprocessed.length > 0) {
      mermaid.run({
        nodes: actuallyUnprocessed
      }).then(() => {
        actuallyUnprocessed.forEach(el => {
          el.classList.add('mermaid-rendered');
          el.setAttribute('data-processed', 'true');
        });
      }).catch(err => {
        console.error("Mermaid: mermaid.run error:", err);
        // Mark as processed to avoid infinite loops if it's a syntax error
        actuallyUnprocessed.forEach(el => el.setAttribute('data-processed', 'true'));
      });
    }
  }, 100);
}

// Global listeners
window.addEventListener("phx:llm_end", renderAll);
window.addEventListener("phx:rendered", renderAll);

export default {
  mounted() {
    renderAll();
  },
  updated() {
    renderAll();
  }
}
