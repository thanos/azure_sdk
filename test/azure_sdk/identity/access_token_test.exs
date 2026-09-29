defmodule AzureSDK.Identity.AccessTokenTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.AccessToken

  test "from_response with expires_in" do
    assert {:ok, token} =
             AccessToken.from_response(%{
               "access_token" => "abc",
               "expires_in" => 3600,
               "token_type" => "Bearer"
             })

    assert token.token == "abc"
    assert DateTime.diff(token.expires_at, DateTime.utc_now(), :second) in 3590..3605
  end

  test "from_response with expires_on unix string" do
    expires_on = DateTime.utc_now() |> DateTime.add(120, :second) |> DateTime.to_unix()

    assert {:ok, token} =
             AccessToken.from_response(%{
               "access_token" => "abc",
               "expires_on" => Integer.to_string(expires_on)
             })

    refute AccessToken.stale?(token, 60)
    assert AccessToken.stale?(token, 300)
  end

  test "rejects missing access_token" do
    assert {:error, %{code: "InvalidTokenResponse"}} = AccessToken.from_response(%{})
  end
end
