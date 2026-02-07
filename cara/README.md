# Cara - The AI Learning Companion

Cara is an AI-powered chat application designed to be a friendly and engaging learning companion for school-aged students. It leverages the power of Large Language Models (LLMs) to provide a personalized learning experience tailored to each student's age and the subject they are studying.

Built with Elixir and the Phoenix Framework, Cara offers a real-time, interactive chat interface where students can ask questions and get clear, helpful explanations.

## Features

- **Personalized Learning:** Cara's personality and response style are dynamically adjusted based on the student's age, making it a more effective and engaging tutor.
- **Real-time Interaction:** The chat interface, built with Phoenix LiveView, provides instant, streaming responses from the AI.
- **Markdown Support:** The AI's responses are rendered as Markdown, allowing for formatted text, code blocks, lists, and more.
- **Extensible by Design:** The core AI interaction is abstracted into a behaviour, making it easy to swap out different LLM backends.

## Technical Overview

Cara is built on a modern Elixir stack:

- **Backend:** Elixir, Phoenix
- **Real-time UI:** Phoenix LiveView
- **Database:** PostgreSQL (via Ecto)
- **AI Integration:** `req_llm` library, configurable to use various LLM providers (defaults to OpenRouter with Mistral).
- **Frontend:** Tailwind CSS and esbuild for asset management.
- **Testing:** A robust test suite using ExUnit, with mocking provided by the Mox library.

## Getting Started

To get Cara up and running on your local machine, follow these steps.

### Prerequisites

- Elixir `~> 1.15`
- Erlang/OTP
- PostgreSQL
- Node.js (for asset building)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/cara.git
    cd cara
    ```

2.  **Install dependencies:**
    This command will fetch all Elixir and Node.js dependencies.
    ```bash
    mix setup
    ```

3.  **Configure your database:**
    Open `config/dev.exs` and update the database configuration to match your local PostgreSQL setup.

4.  **Create and migrate the database:**
    ```bash
    mix ecto.setup
    ```

5.  **Set up your AI provider:**
    Cara uses the `req_llm` library for AI chat. By default, it's configured to use OpenRouter. To make it work, you need to set the `OPENROUTER_API_KEY` environment variable.

    You can get a free key from the [OpenRouter.ai website](https://openrouter.ai/).

    ```bash
    export OPENROUTER_API_KEY="your-key-here"
    ```

    Alternatively, you can configure a different provider (like OpenAI or a local model) by updating the configuration in `config/config.exs`.

6.  **Run the development server:**
    ```bash
    mix phx.server
    ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Running Tests

To run the test suite, use the following command:

```bash
mix test
```

The tests for this project use a mock of the AI chat service to avoid making real API calls. You can see the mock implementation in `test/support/mocks/chat_mock.ex`.

## Project Structure

- `lib/cara`: The core application logic, including the AI chat functionality.
- `lib/cara/ai`: The heart of the AI interaction, including the `Chat` module and prompt generation.
- `lib/cara_web`: The web interface, including controllers, LiveView modules, and templates.
- `lib/cara_web/live/chat_live.ex`: The main LiveView for the chat interface.
- `priv/prompts`: EEx templates for the AI's system prompts.
- `test`: All the application tests.

## How It Works

1.  A user visits the home page and provides their name, age, and the subject they want to learn about.
2.  This information is stored in the session.
3.  When the user enters the chat, a `system_prompt` is generated using the `priv/prompts/greeting.eex` template. This prompt instructs the AI on how to behave based on the user's details.
4.  The `ChatLive` LiveView sends the user's messages to the `Cara.AI.Chat` module.
5.  `Cara.AI.Chat` constructs a request to the configured LLM, including the conversation history and the system prompt.
6.  The response from the LLM is streamed back to the `ChatLive` process, which updates the UI in real-time.

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.