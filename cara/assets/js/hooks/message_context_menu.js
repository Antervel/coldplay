// CSS-based context menu - uses event delegation for all actions
// This hook is attached to the #chat-messages element
export default {
  mounted() {
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
          const branchId = messageWrapper.dataset.branchId || 'main';
          const contextMenu = document.getElementById(`context-menu-${messageId}-${branchId}`);
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
  destroyed() {
    if (this._cleanup) {
      this._cleanup();
    }
  }
};
