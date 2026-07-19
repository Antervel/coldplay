# Reconfiguring `branched_llm` for Multi-Model Support

## Problem

Currently `BranchedLLM.Chat` uses a single global config for the LLM provider
(`:req_llm` → `:openai` → `:base_url` + `openai_api_key`). Switching between
two different providers (e.g. Ollama local and NVIDIA cloud) requires changing
not only the model name/ID but also the **base URL** and **API key**.

## Required Changes in `branched_llm`

### 1. Make `endpoints/0` model-aware

`BranchedLLM.Chat.endpoints/0` currently reads a single `base_url` from config:

```elixir
defp endpoints do
  base_url = Application.get_env(:branched_llm, :base_url)

  config_url =
    if base_url do
      base_url
    else
      :req_llm
      |> Application.get_env(:openai, [])
      |> Keyword.get(:base_url)
    end

  uri = URI.parse(config_url)
  port_str = if uri.port, do: ":#{uri.port}", else: ""
  base_url = "#{uri.scheme}://#{uri.host}#{port_str}"

  %{
    base_url: base_url,
    model_endpoint: base_url <> "/v1",
    health_endpoint: base_url <> "/api/tags"
  }
end
```

It should instead accept a **provider name** (derived from the model string) and
look up the correct config per provider.

**Suggested approach:** Accept `provider` as a parameter and store per-provider
config:

```elixir
config :branched_llm, :providers,
  openai: [
    base_url: "http://host.containers.internal:11434/v1",
    api_key: "ollama"
  ],
  nvidia: [
    base_url: "https://integrate.api.nvidia.com/v1",
    api_key: {:system, "NVIDIA_API_KEY"}
  ]
```

### 2. Pass provider info through to `call_llm`

The `build_config/1` and `call_llm/3` chain already receives a resolved model.
The model string format `"provider:model_id"` (`openai:cara-cpu`) contains the
provider prefix. The flow:

1. `build_config/1` calls `default_model()` which reads
   `Application.get_env(:branched_llm, :ai_model, "openai:cara-cpu")`
2. `resolve_model/1` splits on `:` → `[provider, id]` → calls
   `ReqLLM.model!(%{provider: String.to_atom(provider), id: id})`
3. `call_llm/3` passes the resolved model + `endpoints().model_endpoint` to
   `ReqLLM.stream_text/4`

**What needs to change:**

- `call_llm/3` should extract the **provider** from the model or model string
- Look up the provider's `base_url` and `api_key` from the per-provider config
- Pass the correct `base_url` and `api_key` to `ReqLLM.stream_text/4`

### 3. Support per-provider API keys

Currently the API key is set globally:

```elixir
config :req_llm,
  openai_api_key: "ollama"
```

When calling NVIDIA, the key must be read from `$NVIDIA_API_KEY`. The
`ReqLLM.stream_text/4` function already accepts a `base_url` option. For API
keys, we need to either:

- Set `openai_api_key` at call time (pre-`ReqLLM` call),
- Or pass the key via the request options.

Check if `ReqLLM.stream_text/4` accepts an `api_key` option; if not, set it via
`Application.put_env(:req_llm, :openai_api_key, key)` before each call.

### 4. `default_model/0` should use Cara's config

`BranchedLLM.Chat.default_model/0` currently reads from
`:branched_llm, :ai_model`. Since Cara overrides the model choice globally via
`Application.put_env(:cara, :ai_model, ...)`, the default should fall back to
Cara's config:

```elixir
def default_model do
  Application.get_env(:cara, :ai_model) ||
    Application.get_env(:branched_llm, :ai_model, "openai:cara-cpu")
end
```

### 5. Health check per provider

`health_check/0` pings the Ollama-specific `/api/tags` endpoint. When using
NVIDIA (or any other OpenAI-compatible provider), the health check endpoint
differs. Either:

- Accept a `provider` parameter and use the correct endpoint per provider, or
- Skip health checks for non-Ollama providers.

## Summary of Changes Needed

| Area | Current | Target |
|------|---------|--------|
| `endpoints/0` | Global single `base_url` | Per-provider config lookup |
| `call_llm/3` | One `base_url` for all | Per-provider `base_url` + `api_key` |
| `health_check/0` | Ollama `/api/tags` | Provider-aware check |
| `default_model/0` | `:branched_llm` only | Fallback to `:cara` config |
| API keys | Single global key | Per-provider keys (env vars) |
