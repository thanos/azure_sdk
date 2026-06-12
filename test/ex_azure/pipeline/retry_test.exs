defmodule ExAzure.Pipeline.RetryTest do
  use ExUnit.Case, async: true

  alias ExAzure.Pipeline.Retry

  test "returns default retry policy" do
    assert %{max_attempts: 3, base_delay_ms: 200} = Retry.policy()
  end
end
