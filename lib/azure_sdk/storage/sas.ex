defmodule AzureSDK.Storage.Sas do
  @moduledoc """
  Generates Azure Storage Shared Access Signatures.

  Consumption of existing SAS tokens remains `AzureSDK.Identity.SASCredential`.
  This module creates query strings and credentials from a Shared Key or a
  user-delegation key.

  ## Result (`t:sas_result/0`)

  By default functions return `{:ok, query_string}` suitable for appending to a
  blob URL. Pass `as_credential: true` to receive `{:ok, %SASCredential{}}`.

  ## Examples

      cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))

      {:ok, query} =
        AzureSDK.Storage.Sas.sign_blob(cred,
          container: "uploads",
          blob: "a.txt",
          permissions: "r",
          expiry: ~U[2030-01-01 00:00:00Z]
        )
  """

  alias AzureSDK.Core.{Pipeline, Request}
  alias AzureSDK.Identity.{SASCredential, SharedKeyCredential}
  alias AzureSDK.Storage.{Client, ServiceVersion}

  @typedoc """
  User-delegation key returned by `get_user_delegation_key/2`.

  Opaque map with Azure fields such as `signed_oid`, `signed_tid`,
  `signed_start`, `signed_expiry`, `signed_service`, `signed_version`, and
  `value` (Base64 signing key).
  """
  @opaque user_delegation_key :: %{
            signed_oid: String.t(),
            signed_tid: String.t(),
            signed_start: String.t(),
            signed_expiry: String.t(),
            signed_service: String.t(),
            signed_version: String.t(),
            value: String.t()
          }

  @typedoc """
  SAS generation result: a URL query string, or a `SASCredential` when
  `as_credential: true`.
  """
  @type sas_result :: String.t() | SASCredential.t()

  @doc """
  Signs a blob service SAS using a Shared Key credential.

  ## Parameters

  * `credential` - `AzureSDK.Identity.SharedKeyCredential`
  * `opts` - keyword list (required keys listed below)

  ## Options

  * `:container` (required) - container name
  * `:blob` (required) - blob name
  * `:permissions` (required) - e.g. `"r"`, `"rw"`
  * `:expiry` (required) - `DateTime` UTC
  * `:start` - optional `DateTime` start
  * `:api_version` - service version string (default `ServiceVersion.default/0`)
  * `:protocol` - e.g. `"https"`
  * `:ip` - signed IP or IP range
  * `:as_credential` - when `true`, returns `SASCredential` (default `false`)

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> {:ok, query} = AzureSDK.Storage.Sas.sign_blob(cred,
      ...>   container: "c",
      ...>   blob: "b.txt",
      ...>   permissions: "r",
      ...>   expiry: ~U[2030-01-01 00:00:00Z],
      ...>   start: ~U[2029-01-01 00:00:00Z],
      ...>   ip: "127.0.0.1",
      ...>   protocol: "https"
      ...> )
      iex> params = URI.decode_query(query)
      iex> params["sp"]
      "r"
      iex> params["sr"]
      "b"
      iex> params["sip"]
      "127.0.0.1"

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> {:ok, %AzureSDK.Identity.SASCredential{}} =
      ...>   AzureSDK.Storage.Sas.sign_blob(cred,
      ...>     container: "c",
      ...>     blob: "b.txt",
      ...>     permissions: "r",
      ...>     expiry: ~U[2030-01-01 00:00:00Z],
      ...>     as_credential: true
      ...>   )
  """
  @spec sign_blob(SharedKeyCredential.t(), keyword()) ::
          {:ok, sas_result()} | {:error, AzureSDK.Error.t()}
  def sign_blob(%SharedKeyCredential{} = credential, opts) when is_list(opts) do
    container = Keyword.fetch!(opts, :container)
    blob = Keyword.fetch!(opts, :blob)
    permissions = Keyword.fetch!(opts, :permissions)
    expiry = Keyword.fetch!(opts, :expiry)
    version = Keyword.get(opts, :api_version, ServiceVersion.default())
    canonical = "/blob/#{credential.account}/#{container}/#{blob}"
    sign_service(credential, permissions, expiry, canonical, "b", version, opts)
  end

  @doc """
  Signs a container service SAS using a Shared Key credential.

  ## Parameters

  * `credential` - `AzureSDK.Identity.SharedKeyCredential`
  * `opts` - keyword list

  ## Options

  * `:container` (required)
  * `:permissions` (required) - e.g. `"rl"`
  * `:expiry` (required) - `DateTime` UTC
  * `:start`, `:api_version`, `:protocol`, `:ip`
  * `:as_credential` - when `true`, returns `SASCredential`

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> {:ok, query} = AzureSDK.Storage.Sas.sign_container(cred,
      ...>   container: "c",
      ...>   permissions: "rl",
      ...>   expiry: ~U[2030-01-01 00:00:00Z]
      ...> )
      iex> URI.decode_query(query)["sr"]
      "c"
  """
  @spec sign_container(SharedKeyCredential.t(), keyword()) ::
          {:ok, sas_result()} | {:error, AzureSDK.Error.t()}
  def sign_container(%SharedKeyCredential{} = credential, opts) when is_list(opts) do
    container = Keyword.fetch!(opts, :container)
    permissions = Keyword.fetch!(opts, :permissions)
    expiry = Keyword.fetch!(opts, :expiry)
    version = Keyword.get(opts, :api_version, ServiceVersion.default())
    canonical = "/blob/#{credential.account}/#{container}"
    sign_service(credential, permissions, expiry, canonical, "c", version, opts)
  end

  @doc """
  Requests a user-delegation key from Blob Storage (TokenCredential client).

  ## Parameters

  * `client` - `AzureSDK.Storage.Client` authorized with a TokenCredential
  * `opts` - keyword list

  ## Options

  * `:expiry` (required) - `DateTime` UTC when the key expires
  * `:start` - optional `DateTime` start (default `DateTime.utc_now/0`)

  ## Returns

  * `{:ok, user_delegation_key()}` opaque map for `sign_user_delegation_blob/2`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, udk} =
        AzureSDK.Storage.Sas.get_user_delegation_key(client,
          start: DateTime.utc_now(),
          expiry: DateTime.add(DateTime.utc_now(), 3600, :second)
        )
  """
  @spec get_user_delegation_key(Client.t(), keyword()) ::
          {:ok, user_delegation_key()} | {:error, AzureSDK.Error.t()}
  def get_user_delegation_key(%Client{} = client, opts) when is_list(opts) do
    start = opts |> Keyword.get(:start, DateTime.utc_now()) |> format_iso8601()
    expiry = opts |> Keyword.fetch!(:expiry) |> format_iso8601()

    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <KeyInfo>
      <Start>#{start}</Start>
      <Expiry>#{expiry}</Expiry>
    </KeyInfo>
    """

    request =
      Request.new(
        method: :post,
        path: "/",
        query: [{"restype", "service"}, {"comp", "userdelegationkey"}],
        headers: %{
          "x-ms-version" => client.api_version,
          "Content-Type" => "application/xml",
          "Content-Length" => Integer.to_string(byte_size(body))
        },
        body: body,
        service: :blob,
        operation: :get_user_delegation_key,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, parse_user_delegation_key(response.body || "")}
    end
  end

  @doc """
  Signs a blob user-delegation SAS from a key returned by `get_user_delegation_key/2`.

  ## Parameters

  * `udk` - opaque `user_delegation_key()`
  * `opts` - keyword list

  ## Options

  * `:account` (required) - storage account name
  * `:container` (required)
  * `:blob` (required)
  * `:permissions` (required)
  * `:expiry` (required) - `DateTime` UTC
  * `:start`, `:api_version`, `:protocol`, `:ip`
  * `:as_credential` - when `true`, returns `SASCredential`

  ## Examples

      iex> udk = %{
      ...>   signed_oid: "oid",
      ...>   signed_tid: "tid",
      ...>   signed_start: "2029-01-01T00:00:00Z",
      ...>   signed_expiry: "2030-01-01T00:00:00Z",
      ...>   signed_service: "b",
      ...>   signed_version: "2024-11-04",
      ...>   value: Base.encode64("sixteen-byte-key!")
      ...> }
      iex> {:ok, query} = AzureSDK.Storage.Sas.sign_user_delegation_blob(udk,
      ...>   account: "acct",
      ...>   container: "c",
      ...>   blob: "b.txt",
      ...>   permissions: "r",
      ...>   expiry: ~U[2030-01-01 00:00:00Z]
      ...> )
      iex> params = URI.decode_query(query)
      iex> params["skoid"]
      "oid"
      iex> params["sr"]
      "b"
  """
  @spec sign_user_delegation_blob(user_delegation_key(), keyword()) ::
          {:ok, sas_result()} | {:error, AzureSDK.Error.t()}
  def sign_user_delegation_blob(udk, opts) when is_map(udk) and is_list(opts) do
    account = Keyword.fetch!(opts, :account)
    container = Keyword.fetch!(opts, :container)
    blob = Keyword.fetch!(opts, :blob)
    permissions = Keyword.fetch!(opts, :permissions)
    expiry = Keyword.fetch!(opts, :expiry)
    version = Keyword.get(opts, :api_version, ServiceVersion.default())
    start = Keyword.get(opts, :start)
    canonical = "/blob/#{account}/#{container}/#{blob}"

    string_to_sign =
      Enum.join(
        [
          permissions,
          format_sas_time(start),
          format_sas_time(expiry),
          canonical,
          udk.signed_oid,
          udk.signed_tid,
          udk.signed_start,
          udk.signed_expiry,
          udk.signed_service,
          udk.signed_version,
          "",
          "",
          Keyword.get(opts, :ip, ""),
          Keyword.get(opts, :protocol, ""),
          version,
          "b",
          "",
          "",
          "",
          "",
          "",
          "",
          ""
        ],
        "\n"
      )

    with {:ok, sig} <- hmac_base64(udk.value, string_to_sign) do
      params =
        %{
          "sv" => version,
          "sr" => "b",
          "sp" => permissions,
          "se" => format_sas_time(expiry),
          "skoid" => udk.signed_oid,
          "sktid" => udk.signed_tid,
          "skt" => udk.signed_start,
          "ske" => udk.signed_expiry,
          "sks" => udk.signed_service,
          "skv" => udk.signed_version,
          "sig" => sig
        }
        |> maybe_put_param("st", format_sas_time(start))
        |> maybe_put_param("sip", Keyword.get(opts, :ip))
        |> maybe_put_param("spr", Keyword.get(opts, :protocol))

      finish_sas(params, opts)
    end
  end

  defp sign_service(credential, permissions, expiry, canonical, resource, version, opts) do
    start = Keyword.get(opts, :start)

    string_to_sign =
      Enum.join(
        [
          permissions,
          format_sas_time(start),
          format_sas_time(expiry),
          canonical,
          "",
          Keyword.get(opts, :ip, ""),
          Keyword.get(opts, :protocol, ""),
          version,
          resource,
          "",
          "",
          "",
          "",
          "",
          "",
          ""
        ],
        "\n"
      )

    with {:ok, sig} <- hmac_base64(credential.key, string_to_sign) do
      params =
        %{
          "sv" => version,
          "sr" => resource,
          "sp" => permissions,
          "se" => format_sas_time(expiry),
          "sig" => sig
        }
        |> maybe_put_param("st", format_sas_time(start))
        |> maybe_put_param("sip", Keyword.get(opts, :ip))
        |> maybe_put_param("spr", Keyword.get(opts, :protocol))

      finish_sas(params, opts)
    end
  end

  defp finish_sas(params, opts) do
    if Keyword.get(opts, :as_credential, false) do
      {:ok, SASCredential.new(params)}
    else
      {:ok, URI.encode_query(params)}
    end
  end

  defp hmac_base64(key_b64, string) do
    case Base.decode64(key_b64) do
      {:ok, key} ->
        {:ok, Base.encode64(:crypto.mac(:hmac, :sha256, key, string))}

      :error ->
        {:error,
         AzureSDK.Error.new(
           code: "InvalidCredential",
           message: "SAS signing key is not valid Base64",
           service: :blob
         )}
    end
  end

  defp format_sas_time(nil), do: ""

  defp format_sas_time(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_iso8601(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp maybe_put_param(map, _key, nil), do: map
  defp maybe_put_param(map, _key, ""), do: map
  defp maybe_put_param(map, key, value), do: Map.put(map, key, value)

  defp parse_user_delegation_key(xml) do
    import SweetXml

    %{
      signed_oid: xpath(xml, ~x"//SignedOid/text()"s),
      signed_tid: xpath(xml, ~x"//SignedTid/text()"s),
      signed_start: xpath(xml, ~x"//SignedStart/text()"s),
      signed_expiry: xpath(xml, ~x"//SignedExpiry/text()"s),
      signed_service: xpath(xml, ~x"//SignedService/text()"s),
      signed_version: xpath(xml, ~x"//SignedVersion/text()"s),
      value: xpath(xml, ~x"//Value/text()"s)
    }
  end
end
