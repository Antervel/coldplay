defmodule Cara.Test.StreamResponseHelper do
  @moduledoc """
  Helper for constructing ReqLLM.StreamResponse structs in tests.
  Handles the MetadataHandle GenServer setup required by req_llm >= 1.11.0.
  """

  alias ReqLLM.StreamResponse.MetadataHandle

  @doc """
  Starts a MetadataHandle that returns an empty map, suitable for test StreamResponse structs.
  """
  def start_metadata_handle do
    {:ok, handle} = MetadataHandle.start_link(fn -> %{} end)
    handle
  end
end
