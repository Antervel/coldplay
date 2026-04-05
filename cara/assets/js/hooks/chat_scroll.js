export default {
  mounted() {
    this.isAtBottom = true // Assume at bottom initially
    this.el.addEventListener("scroll", () => {
      // Use a small tolerance for "at bottom" check due to potential floating point inaccuracies
      this.isAtBottom = this.el.scrollHeight - this.el.clientHeight - this.el.scrollTop < 1
    })
    this.scrollToBottom()
  },
  updated() {
    // Check if we *were* at the bottom before the update
    if (this.isAtBottom) {
      this.scrollToBottom()
    }
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
    // After scrolling, we are definitely at the bottom
    this.isAtBottom = true
  }
}
