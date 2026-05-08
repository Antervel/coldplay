/**
 * LLM Chunk Appender Hook
 * 
 * Handles streaming of LLM responses by updating the message content directly
 * in the DOM instead of re-rendering the entire message bubble. This eliminates
 * flickering during streaming.
 * 
 * The hook listens for "llm_chunk" events from LiveView and:
 * 1. Finds the target message content element by ID
 * 2. Updates the element's innerHTML with the full rendered content
 * 3. Updates the MessageContentMap with the new content
 * 
 * Note: We receive the full rendered HTML for the message from Elixir on each chunk,
 * which ensures proper markdown rendering (bold, italics, code blocks, etc.).
 */
export default {
  mounted() {
    // Listen for llm_chunk events from LiveView
    this.handleEvent("llm_chunk", ({ message_id, branch_id, rendered_html }) => {
      this.updateMessageContent(message_id, branch_id, rendered_html);
    });
  },

  /**
   * Updates the message content with the full rendered HTML
   * @param {string} message_id - The ID of the message to update
   * @param {string} branch_id - The branch ID (for debugging/logging)
   * @param {string} rendered_html - The full rendered HTML for the message
   */
  updateMessageContent(message_id, branch_id, rendered_html) {
    if (!message_id) {
      console.warn("LLMChunkAppender: No message_id provided, cannot update message");
      return;
    }

    // Find the message content element
    const contentEl = document.getElementById(`message-content-${message_id}`);
    
    if (!contentEl) {
      console.warn(
        `LLMChunkAppender: Could not find element with ID message-content-${message_id} for branch ${branch_id}`
      );
      return;
    }

    // Update the content with the full rendered HTML
    try {
      // Store the current scroll position and whether we're at the bottom
      const container = contentEl.closest('#chat-messages');
      const wasAtBottom = container && this.isAtBottom(container);
      
      // Update the innerHTML with the new rendered content
      contentEl.innerHTML = rendered_html;
      
      // Update MessageContentMap with the new content
      // We need to extract the text content from the HTML for the map
      if (window.MessageContentMap) {
        // Get the text content (without HTML tags) for the map
        const textContent = contentEl.textContent || '';
        window.MessageContentMap.update(message_id, textContent);
      }
      
      // Scroll to bottom if we were at the bottom before
      if (container && wasAtBottom) {
        setTimeout(() => {
          container.scrollTop = container.scrollHeight;
        }, 0);
      }

      // Debug logging in development
      if (process.env.NODE_ENV === "development") {
        console.debug(
          `LLMChunkAppender: Updated message ${message_id} (branch: ${branch_id})`
        );
      }
    } catch (error) {
      console.error(
        `LLMChunkAppender: Error updating message ${message_id}:`,
        error
      );
    }
  },

  /**
   * Checks if the container is scrolled to the bottom
   * @param {HTMLElement} container - The container element
   * @returns {boolean} - True if at the bottom
   */
  isAtBottom(container) {
    if (!container) return false;
    const { scrollTop, scrollHeight, clientHeight } = container;
    return scrollTop + clientHeight >= scrollHeight - 1;
  }
};
