export default {
  mounted() {
    this.el.addEventListener("input", () => this.resize());
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && e.shiftKey) {
        // Shift+Enter pressed: insert new line
        e.preventDefault(); // Prevent default form submission

        // Manually insert newline
        const start = this.el.selectionStart;
        const end = this.el.selectionEnd;
        this.el.value = this.el.value.substring(0, start) + "\n" + this.el.value.substring(end);
        this.el.selectionStart = this.el.selectionEnd = start + 1;

        // Also update LiveView's internal state for `message_data`
        // Push a validate event with the updated value
        this.pushEvent("validate", { chat: { message: this.el.value } });
        this.resize(); // Resize after adding a new line
      } else if (e.key === "Enter" && !e.shiftKey && !e.ctrlKey) {
        // Enter pressed alone (without Shift or Ctrl): submit form
        this.pushEvent("submit_message", { message: this.el.value });
        this.el.value = ""; // Clear input immediately
        e.preventDefault(); // Prevent default Enter behavior (newline)
        this.resize(); // Resize after clearing the input
      }
    });
    this.resize(); // Initial resize on mount
  },
  updated() {
    this.resize(); // Resize on LiveView updates
  },
  resize() {
    this.el.style.height = 'auto'; // Reset height to recalculate
    this.el.style.height = this.el.scrollHeight + 'px';
  },
}
