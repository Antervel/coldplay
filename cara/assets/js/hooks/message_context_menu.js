export default {
  mounted() {
    const contextMenu = document.getElementById('message-context-menu');
    let currentMessageEl = null;

    const hideContextMenu = () => {
      contextMenu.classList.remove('opacity-100', 'scale-100');
      contextMenu.classList.add('opacity-0', 'scale-95');

      // Add hidden after a short delay to allow transition to complete
      setTimeout(() => {
        contextMenu.classList.add('hidden');
        currentMessageEl = null;
      }, 300); // Match this delay to the Tailwind transition duration (duration-300)
    };

    const showContextMenu = (event) => {
      const triggerButton = event.target.closest('[data-action="open-context-menu"]');
      if (!triggerButton) return;

      event.preventDefault();
      event.stopPropagation(); // Stop propagation to prevent document click from closing immediately

      // If the menu is already open for THIS message, close it.
      if (!contextMenu.classList.contains('hidden') && currentMessageEl === this.el) {
        hideContextMenu();
        return;
      }

      currentMessageEl = this.el; // Still need the message element for data-message-content
      const messageContent = currentMessageEl.dataset.messageContent;

      // Make visible first (remove display: none), then allow browser to paint, then apply transition classes
      contextMenu.classList.remove('hidden');
      // Force reflow/repaint to ensure 'display' change is registered before applying opacity/scale
      contextMenu.offsetWidth; // This forces a reflow. Without this, the transition won't work on 'display' change.

      contextMenu.classList.remove('opacity-0', 'scale-95');
      contextMenu.classList.add('opacity-100', 'scale-100');

      const triggerButtonRect = triggerButton.getBoundingClientRect();
      const contextMenuRect = contextMenu.getBoundingClientRect(); // Get dimensions AFTER removing hidden and setting opacity/scale

      contextMenu.style.top = `${triggerButtonRect.bottom + window.scrollY + 5}px`;

      // Check if the message is from the user or AI to adjust horizontal position
      const isUserMessage = currentMessageEl.dataset.sender === 'user';

      let finalLeft;
      const padding = 10; // Padding from viewport edges

      if (isUserMessage) {
        // Attempt to align the right of the context menu with the right of the button
        finalLeft = triggerButtonRect.right - contextMenuRect.width + window.scrollX;
      } else {
        // Attempt to align the left of the context menu with the left of the button
        finalLeft = triggerButtonRect.left + window.scrollX;
      }

      // Apply left constraint
      if (finalLeft < padding) {
        finalLeft = padding;
      }

      // Apply right constraint
      // The right edge of the menu is finalLeft + contextMenuRect.width
      if (finalLeft + contextMenuRect.width > window.innerWidth - padding) {
        finalLeft = window.innerWidth - contextMenuRect.width - padding;
      }

      // Ensure finalLeft doesn't become negative if menu is wider than viewport,
      // or if the right constraint pushed it too far left.
      // This effectively re-applies the left constraint after the right one.
      if (finalLeft < padding) {
        finalLeft = padding;
      }

      contextMenu.style.left = `${finalLeft}px`;

      // Show/hide Delete button based on sender
      const deleteButton = contextMenu.querySelector('[data-action="delete"]');
      if (deleteButton) {
        deleteButton.classList.remove('hidden');
      }

      // Attach actions to buttons
      contextMenu.querySelector('[data-action="copy"]').onclick = async (e) => {
        e.stopPropagation();
        try {
          await navigator.clipboard.writeText(messageContent);
          console.log("Message copied to clipboard:", messageContent);
          // Optional: Add visual feedback for copied content
        } catch (err) {
          console.error("Failed to copy message:", err);
          // Optional: Handle error, e.g., show a toast notification
        }
        hideContextMenu();
      };

      contextMenu.querySelector('[data-action="play"]').onclick = (e) => {
        e.stopPropagation();
        if ('speechSynthesis' in window) {
          const cleanedMessageContent = messageContent.replace(/\p{Emoji_Modifier_Base}\p{Emoji_Modifier}?\p{Emoji}-\uFE0F\p{Emoji}?\u200D|\p{Emoji_Modifier_Base}\p{Emoji_Modifier}?|\p{Emoji_Presentation}|\p{Emoji}\uFE0F/gu, '');
          const utterance = new SpeechSynthesisUtterance(cleanedMessageContent);
          utterance.rate = 0.9;   // Make it speak slower (default is 1)
          utterance.pitch = 1.5;  // Slightly higher pitch for a "sweeter" voice (default is 1, range 0-2)
          // Optional: Configure other utterance properties or select a specific voice
          // utterance.lang = 'en-US'; // Set language
          window.speechSynthesis.speak(utterance);
          console.log("Playing message:", cleanedMessageContent);

          utterance.onend = () => {
            console.log("Speech finished.");
          };
          utterance.onerror = (event) => {
            console.error("SpeechSynthesisUtterance.onerror", event);
          };

        } else {
          console.warn("Speech Synthesis API not supported in this browser.");
          alert("Your browser does not support the Web Speech API for text-to-speech.");
        }
        hideContextMenu();
      };

      if (deleteButton) {
        deleteButton.onclick = (e) => {
          e.stopPropagation();
          const id = currentMessageEl.dataset.id;
          this.pushEvent("delete_message", { id: id });
          hideContextMenu();
        };
      }

      const branchButton = contextMenu.querySelector('[data-action="branch"]');
      if (branchButton) {
        branchButton.onclick = (e) => {
          e.stopPropagation();
          const id = currentMessageEl.dataset.id;
          this.pushEvent("branch_off", { id: id });
          hideContextMenu();
        };
      }
    };

    this.el.addEventListener('click', showContextMenu);
    this.el.addEventListener('touchstart', showContextMenu); // For touch devices

    // Close menu when clicking anywhere else on the document
    this._handleDocumentClick = (event) => {
      if (!contextMenu.contains(event.target) && !this.el.contains(event.target)) {
        hideContextMenu();
      }
    };
    document.addEventListener('click', this._handleDocumentClick);
    document.addEventListener('touchstart', this._handleDocumentClick);

    this.handleEvent("hide_context_menu", () => {
      hideContextMenu();
    });
  },
  destroyed() {
    if (this._handleDocumentClick) {
      document.removeEventListener('click', this._handleDocumentClick);
      document.removeEventListener('touchstart', this._handleDocumentClick);
    }
  }
}
