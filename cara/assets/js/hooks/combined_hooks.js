/**
 * Combined Hook for MessageContextMenu and LLMChunkAppender
 *
 * This hook combines both MessageContextMenu and LLMChunkAppender functionality
 * to work around the Phoenix LiveView limitation of one phx-hook per element.
 *
 * MessageContextMenu handles:
 * - Opening/closing context menus for messages
 * - Copy, Play, Branch, Delete actions via event delegation
 *
 * LLMChunkAppender handles:
 * - Streaming LLM responses by updating message content directly
 * - Eliminates flickering during streaming
 */
// Note: MessageContentMap is already available globally via window.MessageContentMap
// It's set up in app.js from the import in hooks/index.js

import katex from "katex";

// Helper function to render KaTeX on an element
const renderKaTeX = (el) => {
  const latex = el.dataset.latex;
  const mathStyle = el.dataset.mathStyle;
  if (latex && mathStyle) {
    const displayMode = mathStyle === "display";
    // Trim whitespace from the latex content to handle cases where
    // the original input had spaces like "$ content $" which results
    // in data-latex=" content " (with spaces)
    const trimmedLatex = latex.trim();
    katex.render(trimmedLatex, el, { 
      displayMode: displayMode, 
      throwOnError: false, 
      trust: true, 
    });
  }
};

// Helper function to render all KaTeX elements within a container
const renderAllKaTeXInContainer = (container) => {
  if (!container) return;
  // Find all katex elements (both block and inline) that have data-latex
  container.querySelectorAll('.katex-block[data-latex], .katex-inline[data-latex]').forEach(el => {
    renderKaTeX(el);
  });
};

export default {
  mounted() {
    // Initialize MessageContextMenu functionality
    this.initMessageContextMenu();
    // Initialize LLMChunkAppender functionality
    this.initLLMChunkAppender();
  },

  initMessageContextMenu() {
    // Close all context menus when clicking anywhere on the document
    const hideAllContextMenus = () => {
      document.querySelectorAll('[id^="context-menu-"]').forEach(menu => {
        menu.classList.remove('block');
        menu.classList.add('hidden');
      });
    };

    // Handle click on context menu button (open/close)
    const handleContextMenuButtonClick = (event) => {
      const menuButton = event.target.closest('[data-action="open-context-menu"]');
      if (menuButton) {
        event.preventDefault();
        event.stopPropagation();
        // Find the parent message wrapper
        const messageWrapper = menuButton.closest('[id^="message-wrapper-"]');
        if (messageWrapper) {
          const messageId = messageWrapper.dataset.id;
          const contextMenu = document.getElementById(`context-menu-${messageId}`);
          if (contextMenu) {
            // If this menu is already open, close it
            if (!contextMenu.classList.contains('hidden')) {
              contextMenu.classList.remove('block');
              contextMenu.classList.add('hidden');
              return;
            }
            // Hide all other menus first
            hideAllContextMenus();
            // Show this menu
            contextMenu.classList.remove('hidden');
            contextMenu.classList.add('block');
          }
        }
      }
    };

    // Handle copy action
    const handleCopyClick = (event) => {
      const copyButton = event.target.closest('[data-action="copy"]');
      if (copyButton) {
        event.preventDefault();
        event.stopPropagation();
        const messageId = copyButton.dataset.id;
        const messageContent = window.MessageContentMap ? window.MessageContentMap.get(messageId) : copyButton.dataset.messageContent;
        if (messageContent) {
          navigator.clipboard.writeText(messageContent).then(() => {
            console.log("Message copied to clipboard");
          }).catch(err => {
            console.error("Failed to copy message:", err);
          });
        }
        hideAllContextMenus();
      }
    };

    // Handle play action (text-to-speech)
    const handlePlayClick = (event) => {
      const playButton = event.target.closest('[data-action="play"]');
      if (playButton) {
        event.preventDefault();
        event.stopPropagation();
        const messageId = playButton.dataset.id;
        const messageContent = window.MessageContentMap ? window.MessageContentMap.get(messageId) : playButton.dataset.messageContent;
        if (messageContent && 'speechSynthesis' in window) {
          // Remove emoji modifiers for better TTS
          const cleanedMessageContent = messageContent.replace(/\p{Emoji_Modifier_Base}\p{Emoji_Modifier}?\p{Emoji}-\uFE0F\p{Emoji}?\u200D|\p{Emoji_Modifier_Base}\p{Emoji_Modifier}?|\p{Emoji_Presentation}|\p{Emoji}\uFE0F/gu, '');
          const utterance = new SpeechSynthesisUtterance(cleanedMessageContent);
          utterance.rate = 0.9;
          utterance.pitch = 1.5;
          window.speechSynthesis.speak(utterance);
          utterance.onend = () => console.log("Speech finished.");
          utterance.onerror = (e) => console.error("SpeechSynthesis error:", e);
        } else if (!('speechSynthesis' in window)) {
          console.warn("Speech Synthesis API not supported");
          alert("Your browser does not support the Web Speech API for text-to-speech.");
        }
        hideAllContextMenus();
      }
    };

    // Handle branch action
    const handleBranchClick = (event) => {
      const branchButton = event.target.closest('[data-action="branch"]');
      if (branchButton) {
        event.preventDefault();
        event.stopPropagation();
        const messageId = branchButton.dataset.id;
        if (messageId) {
          // Use this.pushEvent to send to LiveView
          this.pushEvent("branch_off", { id: messageId });
        }
        hideAllContextMenus();
      }
    };

    // Handle delete action
    const handleDeleteClick = (event) => {
      const deleteButton = event.target.closest('[data-action="delete"]');
      if (deleteButton) {
        event.preventDefault();
        event.stopPropagation();
        const messageId = deleteButton.dataset.id;
        if (messageId) {
          // Use this.pushEvent to send to LiveView
          this.pushEvent("delete_message", { id: messageId });
        }
        hideAllContextMenus();
      }
    };

    // Close menus when clicking outside
    const handleDocumentClick = (event) => {
      // Check if click is inside a context menu or on a menu button
      const isContextMenuClick = event.target.closest('[id^="context-menu-"]');
      const isMenuButtonClick = event.target.closest('[data-action="open-context-menu"]');
      // If click is outside, hide all menus
      if (!isContextMenuClick && !isMenuButtonClick) {
        hideAllContextMenus();
      }
    };

    // Add event listeners
    document.addEventListener('click', handleDocumentClick);
    document.addEventListener('click', handleContextMenuButtonClick);
    document.addEventListener('click', handleCopyClick);
    document.addEventListener('click', handlePlayClick);
    document.addEventListener('click', handleBranchClick);
    document.addEventListener('click', handleDeleteClick);

    // Store cleanup function
    this._cleanup = () => {
      document.removeEventListener('click', handleDocumentClick);
      document.removeEventListener('click', handleContextMenuButtonClick);
      document.removeEventListener('click', handleCopyClick);
      document.removeEventListener('click', handlePlayClick);
      document.removeEventListener('click', handleBranchClick);
      document.removeEventListener('click', handleDeleteClick);
    };
  },

  initLLMChunkAppender() {
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
      console.warn("CombinedHook: No message_id provided, cannot update message");
      return;
    }

    // Find the message content element
    const contentEl = document.getElementById(`message-content-${message_id}`);
    if (!contentEl) {
      console.warn(
        `CombinedHook: Could not find element with ID message-content-${message_id} for branch ${branch_id}`
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

      // Render any KaTeX elements in the newly inserted content
      renderAllKaTeXInContainer(contentEl);

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
          `CombinedHook: Updated message ${message_id} (branch: ${branch_id})`
        );
      }
    } catch (error) {
      console.error(
        `CombinedHook: Error updating message ${message_id}:`,
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
  },

  destroyed() {
    if (this._cleanup) {
      this._cleanup();
    }
  }
};
