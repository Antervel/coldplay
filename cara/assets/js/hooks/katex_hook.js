import katex from "katex";

const renderKaTeX = (el) => {
  const latex = el.dataset.latex;
  const mathStyle = el.dataset.mathStyle;
  if (latex && mathStyle) {
    const displayMode = mathStyle === "display";
    katex.render(latex, el, {
      displayMode: displayMode,
      throwOnError: false,
      trust: true,
    });
  }
}

export default {
  mounted() {
    renderKaTeX(this.el);
  }, 
  updated() {
    renderKaTeX(this.el);
  }
}
