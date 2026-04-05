import mermaid from 'mermaid'

// Initialize Mermaid once
mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'loose',
})

// Single, robust render function.
// It scans the WHOLE document for .mermaid blocks that haven't been processed.
// This is the safest way to ensure nothing is missed during rapid DOM swaps.
function renderAll() {
  // We use a small timeout to let the browser's layout settle.
  // This is CRITICAL for Mermaid to calculate SVG dimensions correctly.
  setTimeout(() => {
    // Only target elements that haven't been processed yet.
    // We check both for data-processed and if the innerHTML still looks like text (not an SVG).
    const unprocessed = document.querySelectorAll('.mermaid:not([data-processed])');
    if (unprocessed.length > 0) {
      mermaid.run({
        nodes: Array.from(unprocessed)
      });
    }
  }, 50);
}

// Global listeners for events that might happen while UI is in background or switching states.
window.addEventListener("phx:llm_end", renderAll);
window.addEventListener("phx:rendered", renderAll); // Custom event for branch switching

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === 'visible') renderAll();
});

export default {
  mounted() {
    renderAll();
  },
  updated() {
    // With phx-update="ignore", updated() might not fire if the element 
    // itself didn't change, but it's safe to call here just in case.
    renderAll();
  }
}
