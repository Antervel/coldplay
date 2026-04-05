import mermaid from 'mermaid'

// Run mermaid when the LLM ends its answer (and sends `phx:llm_end` event)
mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'loose',
})

window.mermaid = mermaid;
mermaid.run();
window.addEventListener("phx:llm_end", () => mermaid.run());

export default {
  mounted() {
    mermaid.run({
      querySelector: '.mermaid'
    });
  }
}
