// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/cara"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let Hooks = {}
Hooks.ChatScroll = {
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

Hooks.ChatInput = {
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
};

Hooks.MessageContextMenu = {
  mounted() {
    const contextMenu = document.getElementById('message-context-menu');
    let currentMessageEl = null;

    const showContextMenu = (event) => {
      event.preventDefault();
      event.stopPropagation(); // Stop propagation to prevent document click from closing immediately

      currentMessageEl = this.el;
      const messageContent = currentMessageEl.dataset.messageContent;

      contextMenu.classList.remove('hidden'); // Ensure menu is visible to get accurate dimensions
      // Position the context menu
      const messageBubbleEl = currentMessageEl.firstElementChild;
      const messageBubbleRect = messageBubbleEl.getBoundingClientRect();
      const contextMenuRect = contextMenu.getBoundingClientRect(); // Get context menu's current dimensions

      contextMenu.style.top = `${messageBubbleRect.bottom + window.scrollY + 5}px`;

      // Check if the message is from the user or AI to adjust horizontal position
      const isUserMessage = currentMessageEl.classList.contains('justify-end');

      if (isUserMessage) {
        // For user messages (justify-end), align the right of the context menu with the right of the message bubble
        contextMenu.style.left = `${messageBubbleRect.right - contextMenuRect.width + window.scrollX}px`;
      } else {
        // For AI messages (justify-start), align the left of the context menu with the left of the message bubble
        contextMenu.style.left = `${messageBubbleRect.left + window.scrollX}px`;
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
    };

    const hideContextMenu = () => {
      contextMenu.classList.add('hidden');
      currentMessageEl = null;
    };

    this.el.addEventListener('click', showContextMenu);
    this.el.addEventListener('touchstart', showContextMenu); // For touch devices

    // Close menu when clicking anywhere else on the document
    document.addEventListener('click', (event) => {
      if (!contextMenu.contains(event.target) && !this.el.contains(event.target)) {
        hideContextMenu();
      }
    });
    document.addEventListener('touchstart', (event) => {
      if (!contextMenu.contains(event.target) && !this.el.contains(event.target)) {
        hideContextMenu();
      }
    });

    this.handleEvent("hide_context_menu", () => {
      hideContextMenu();
    });
  },
  destroyed() {
    // Clean up event listeners if necessary, though in LiveView context,
    // new elements/hooks might be mounted more often than destroyed.
    // For simplicity, document listeners are typically fine to remain
    // as they handle closing multiple menus.
  }
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

