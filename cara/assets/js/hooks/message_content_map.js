/**
 * Message Content Map
 * 
 * Stores message content in a JavaScript map to avoid storing large content in DOM data attributes.
 * This reduces memory usage and prevents unnecessary re-renders during LLM streaming.
 * 
 * Usage:
 *   - MessageContentMap.update(messageId, content) - Update content for a message
 *   - MessageContentMap.get(messageId) - Get content for a message
 *   - MessageContentMap.delete(messageId) - Remove content for a message
 *   - MessageContentMap.clear() - Clear all content
 */

const messageContentMap = new Map();

// Update or add content for a message
function update(messageId, content) {
  messageContentMap.set(messageId, content);
}

// Get content for a message
function get(messageId) {
  return messageContentMap.get(messageId);
}

// Remove content for a message
function remove(messageId) {
  messageContentMap.delete(messageId);
}

// Clear all content
function clear() {
  messageContentMap.clear();
}

// Check if content exists for a message
function has(messageId) {
  return messageContentMap.has(messageId);
}

// Get all message IDs
function getAllIds() {
  return Array.from(messageContentMap.keys());
}

// Export the API
export default {
  update,
  get,
  remove,
  clear,
  has,
  getAllIds,
  // Expose the map for debugging in development
  ...(process.env.NODE_ENV === 'development' ? { _map: messageContentMap } : {})
};
