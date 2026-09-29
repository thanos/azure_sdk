defmodule AzureSDK.Storage.ServiceVersion do
  @moduledoc """
  Azure Storage REST API versions recognized by AzureSDK.

  The default is the newest version validated against Azurite in CI. Pass
  `:api_version` to `AzureSDK.Storage.Client.new/1` to override.

  ## Examples

      iex> AzureSDK.Storage.ServiceVersion.default()
      "2024-11-04"
  """

  @latest_validated "2024-11-04"

  @known_versions [
    "2024-11-04",
    "2021-08-06",
    "2020-10-02",
    "2019-12-12"
  ]

  @doc """
  Returns the default (CI-validated) Storage API version.

  ## Examples

      iex> is_binary(AzureSDK.Storage.ServiceVersion.default())
      true
  """
  @spec default() :: String.t()
  def default, do: @latest_validated

  @doc """
  Returns known Storage API versions, newest first.

  ## Examples

      iex> "2024-11-04" in AzureSDK.Storage.ServiceVersion.known_versions()
      true
  """
  @spec known_versions() :: [String.t()]
  def known_versions, do: @known_versions

  @doc """
  Validates a version string.

  ## Parameters

  * `version` — Storage API version string such as `"2024-11-04"`

  ## Returns

  The same `version` string when it is listed in `known_versions/0`.

  ## Errors

  Raises `ArgumentError` when the version is not known. Prefer `validate/1`
  when callers should handle unknown versions without raising.

  ## Examples

      iex> AzureSDK.Storage.ServiceVersion.validate!("2021-08-06")
      "2021-08-06"
      iex> AzureSDK.Storage.ServiceVersion.validate!("1999-01-01")
      ** (ArgumentError) Unknown Storage API version "1999-01-01". Known: ["2024-11-04", "2021-08-06", "2020-10-02", "2019-12-12"]
  """
  @spec validate!(String.t()) :: String.t()
  def validate!(version) when is_binary(version) do
    if version in @known_versions do
      version
    else
      raise ArgumentError,
            "Unknown Storage API version #{inspect(version)}. Known: #{inspect(@known_versions)}"
    end
  end

  @doc """
  Soft-validates a version string.

  ## Returns

  * `{:ok, version}` when known
  * `{:error, :unknown_version}` otherwise

  ## Examples

      iex> AzureSDK.Storage.ServiceVersion.validate("2024-11-04")
      {:ok, "2024-11-04"}
      iex> AzureSDK.Storage.ServiceVersion.validate("1999-01-01")
      {:error, :unknown_version}
  """
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, :unknown_version}
  def validate(version) when is_binary(version) do
    if version in @known_versions, do: {:ok, version}, else: {:error, :unknown_version}
  end
end
