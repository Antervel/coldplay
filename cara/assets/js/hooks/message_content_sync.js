/**
 * Message Content Sync Hook
 * 
 * Updates the MessageContentMap with message content when messages are rendered or updated.
 * This hook should be attached to the message content container to capture content changes.
 * 
 * When a message is mounted or updated:
 *   - Extracts the message ID from the parent wrapper
 *   - Extracts the raw content from the message
 *   - Updates the MessageContentMap with the content
 */

export default {
  mounted() {
    this.syncContent();
  },
  
  updated() {
    this.syncContent();
  },
  
  syncContent() {
    // Get message ID from parent wrapper
    const wrapper = this.el.closest('[data-message-id]');
    if (!wrapper) {
      console.warn('MessageContentSync: Could not find parent message wrapper');
      return;
    }
    
    const messageId = wrapper.dataset.messageId;
    if (!messageId) {
      console.warn('MessageContentSync: Message wrapper missing data-message-id');
      return;
    }
    
    // Get the text content from the element
    // This will be the rendered markdown text
    const content = this.el.textContent || '';
    
    // Update the map
    if (window.MessageContentMap) {
      window.MessageContentMap.update(messageId, content);
    }
  }
};
