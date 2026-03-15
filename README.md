# Coldplay ❄️

**Coldplay** is the parent project for **Cara**, a safe, AI-powered educational companion designed for school-aged students. It provides an engaging learning environment with built-in teacher oversight and advanced content filtering.

## 🌟 Overview

The core of Coldplay is **Cara**, a chat application that leverages Large Language Models (LLMs) to act as a personalized tutor. Cara adjusts its personality and response style based on the student's age and the subject being studied, ensuring that complex topics are explained in an age-appropriate and encouraging way.

### Key Features
- **🎓 Personalized Tutoring:** Dynamic AI personality adjustment based on student age and subject.
- **⚡ Real-time Interaction:** Built with Phoenix LiveView for instant, streaming AI responses.
- **🛡️ Safety First:** Multi-layer filtering pipeline including a keyword blacklist and a "Censor AI" for contextual safety.
- **👨‍🏫 Teacher Oversight:** Designed for classroom environments with real-time monitoring capabilities (see [ARCHITECTURE.md](ARCHITECTURE.md)).
- **🧩 Extensible AI:** Abstracted LLM integration, defaulting to **Ollama** (`cara-cpu` model) for local, private execution.

---

## 🏗️ Project Structure

This repository is organized as a monorepo:

- **[`/cara`](./cara):** The main application (Elixir/Phoenix). Contains the web interface, AI logic, and filtering services.
- **[`/deployment`](./deployment):** Infrastructure and deployment configurations (Docker Compose, environment samples).
- **[`/docs`](./ARCHITECTURE.md):** Detailed technical documentation and architectural diagrams.

---

## 🚀 Quick Start

### Prerequisites
- [Elixir](https://elixir-lang.org/install.html) ~> 1.15 & Erlang/OTP
- [PostgreSQL](https://www.postgresql.org/) (or Docker)
- [Node.js](https://nodejs.org/) (for frontend assets)
- [Ollama](https://ollama.com/)

### Setup with Docker (Recommended for DB)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Antervel/coldplay.git
   cd coldplay
   ```

2. **Start the Database:**
   ```bash
   cd deployment
   cp .env.sample .env # Edit if needed
   docker compose up -d
   cd ..
   ```

3. **Set up Ollama & the Model:**
   ```bash
   # In another terminal
   ollama serve
   # In the project root
   cd cara
   ollama create cara-cpu -f Modelfile
   cd ..
   ```

4. **Configure & Run the App:**
   ```bash
   cd cara
   mix setup
   export OLLAMA_URL="http://localhost:11434/v1"
   mix phx.server
   ```
   Visit [`localhost:4000`](http://localhost:4000) to start chatting with Cara!

---

## 🛠️ Tech Stack

- **Backend:** [Elixir](https://elixir-lang.org/) & [Phoenix Framework](https://www.phoenixframework.org/)
- **Real-time UI:** [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view)
- **Database:** [PostgreSQL](https://www.postgresql.org/)
- **Styling:** [Tailwind CSS](https://tailwindcss.com/) & [DaisyUI](https://daisyui.com/)
- **AI Integration:** [`req_llm`](https://github.com/woylie/req_llm)

---

## 📖 Documentation

- **[Architecture Guide](./ARCHITECTURE.md):** Deep dive into the system design and filtering pipeline.
- **[Cara Application README](./cara/README.md):** Detailed info on the Elixir codebase and development.
- **[Deployment Guide](./deployment/README.md):** Instructions for production-ready setups.
- **[Contributing](./cara/HACKING.md):** Guidelines for developers.

---

## 🔒 Security

We take student safety seriously. For details on our security practices or to report a vulnerability, please see our [SECURITY.md](SECURITY.md).

---

Built with ❤️ for the next generation of learners.
