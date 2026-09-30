defmodule AzureSDK.Storage.Sas do
  @moduledoc """
  Generates Azure Storage Shared Access Signatures.

  Consumption of existing SAS tokens remains `AzureSDK.Identity.SASCredential`.
  This module creates query strings and credentials from a Shared Key or a
  user-delegation key.

  ## Result (`t:sas_result/0`)

  By default functions return `{:ok, query_string}` suitable for appending to a
  blob URL. Pass `as_credential: true` to receive `{:ok, %SASCredential{}}`.

  ## Inputs

  * Times are `DateTime`s in any zone; they are signed as UTC.
  * Permissions may be given in any order and are normalized to the order the
    service requires (`racwdxyltmeopi`). Unknown letters are rejected.
  * A missing required option returns
    `{:error, %AzureSDK.Error{code: "InvalidArgument"}}`; nothing raises.

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

  alias AzureSDK.Error
  alias AzureSDK.Identity.{SASCredential, SharedKeyCredential}
  alias AzureSDK.Storage.{Client, Operation, ServiceVersion}

  @permission_order ~c"racwdxyltmeopi"

  @typedoc """
  User-delegation key returned by `get_user_delegation_key/2`.

  Map with the Azure fields `signed_oid`, `signed_tid`,
  `signed_start`, `signed_expiry`, `signed_service`, `signed_version`, and
  `value` (Base64 signing key).
  """
  @type user_delegation_key :: %{
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
  * `:expiry` (required) - `DateTime` (any zone; signed as UTC)
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
    with {:ok, req} <-
           Operation.require_opts(opts, [:container, :blob, :permissions, :expiry], :blob) do
      canonical = "/blob/#{credential.account}/#{req.container}/#{req.blob}"
      sign_service(credential, req, canonical, "b", opts)
    end
  end

  @doc """
  Signs a container service SAS using a Shared Key credential.

  ## Parameters

  * `credential` - `AzureSDK.Identity.SharedKeyCredential`
  * `opts` - keyword list

  ## Options

  * `:container` (required)
  * `:permissions` (required) - e.g. `"rl"`
  * `:expiry` (required) - `DateTime` (any zone; signed as UTC)
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
    with {:ok, req} <- Operation.require_opts(opts, [:container, :permissions, :expiry], :blob) do
      canonical = "/blob/#{credential.account}/#{req.container}"
      sign_service(credential, req, canonical, "c", opts)
    end
  end

  @doc """
  Requests a user-delegation key from Blob Storage (TokenCredential client).

  ## Parameters

  * `client` - `AzureSDK.Storage.Client` authorized with a TokenCredential
  * `opts` - keyword list

  ## Options

  * `:expiry` (required) - `DateTime` (any zone; signed as UTC) when the key expires
  * `:start` - optional `DateTime` start (default `DateTime.utc_now/0`)

  ## Returns

  * `{:ok, user_delegation_key()}` for `sign_user_delegation_blob/2`
  * `{:error, %AzureSDK.Error{code: "InvalidResponse"}}` when the response is
    not a user delegation key
  * `{:error, %AzureSDK.Error{}}` for other failures

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
    with {:ok, %{expiry: expiry}} <- Operation.require_opts(opts, [:expiry], :blob) do
      start = Keyword.get(opts, :start, DateTime.utc_now())

      body = """
      <?xml version="1.0" encoding="utf-8"?>
      <KeyInfo>
        <Start>#{Operation.iso8601_utc(start)}</Start>
        <Expiry>#{Operation.iso8601_utc(expiry)}</Expiry>
      </KeyInfo>
      """

      with {:ok, response} <-
             Operation.run(client,
               method: :post,
               path: "/",
               query: [{"restype", "service"}, {"comp", "userdelegationkey"}],
               headers: %{
                 "Content-Type" => "application/xml",
                 "Content-Length" => Integer.to_string(byte_size(body))
               },
               body: body,
               operation: :get_user_delegation_key
             ) do
        parse_user_delegation_key(response.body || "")
      end
    end
  end

  @doc """
  Signs a blob user-delegation SAS from a key returned by `get_user_delegation_key/2`.

  ## Parameters

  * `udk` - `user_delegation_key()`
  * `opts` - keyword list

  ## Options

  * `:account` (required) - storage account name
  * `:container` (required)
  * `:blob` (required)
  * `:permissions` (required)
  * `:expiry` (required) - `DateTime`
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
    required = [:account, :container, :blob, :permissions, :expiry]

    with {:ok, req} <- Operation.require_opts(opts, required, :blob),
         {:ok, permissions} <- normalize_permissions(req.permissions) do
      version = Keyword.get(opts, :api_version, ServiceVersion.default())
      start = format_time(Keyword.get(opts, :start))
      expiry = format_time(req.expiry)

      # Field order for service versions 2020-12-06 and later.
      fields = [
        signed_permissions: permissions,
        signed_start: start,
        signed_expiry: expiry,
        canonicalized_resource: "/blob/#{req.account}/#{req.container}/#{req.blob}",
        signed_key_object_id: udk.signed_oid,
        signed_key_tenant_id: udk.signed_tid,
        signed_key_start: udk.signed_start,
        signed_key_expiry: udk.signed_expiry,
        signed_key_service: udk.signed_service,
        signed_key_version: udk.signed_version,
        signed_authorized_user_object_id: "",
        signed_unauthorized_user_object_id: "",
        signed_correlation_id: "",
        signed_ip: Keyword.get(opts, :ip, ""),
        signed_protocol: Keyword.get(opts, :protocol, ""),
        signed_version: version,
        signed_resource: "b",
        signed_snapshot_time: "",
        signed_encryption_scope: "",
        rscc: "",
        rscd: "",
        rsce: "",
        rscl: "",
        rsct: ""
      ]

      with {:ok, sig} <- hmac_base64(udk.value, string_to_sign(fields)) do
        %{
          "sv" => version,
          "sr" => "b",
          "sp" => permissions,
          "se" => expiry,
          "skoid" => udk.signed_oid,
          "sktid" => udk.signed_tid,
          "skt" => udk.signed_start,
          "ske" => udk.signed_expiry,
          "sks" => udk.signed_service,
          "skv" => udk.signed_version,
          "sig" => sig
        }
        |> put_optional_params(start, opts)
        |> finish_sas(opts)
      end
    end
  end

  @doc false
  # Joins string-to-sign fields with newlines. Exposed for known-answer tests.
  @spec string_to_sign(keyword(String.t())) :: String.t()
  def string_to_sign(fields), do: fields |> Keyword.values() |> Enum.join("\n")

  defp sign_service(credential, req, canonical, resource, opts) do
    with {:ok, permissions} <- normalize_permissions(req.permissions) do
      version = Keyword.get(opts, :api_version, ServiceVersion.default())
      start = format_time(Keyword.get(opts, :start))
      expiry = format_time(req.expiry)

      # Field order for service versions 2020-12-06 and later.
      fields = [
        signed_permissions: permissions,
        signed_start: start,
        signed_expiry: expiry,
        canonicalized_resource: canonical,
        signed_identifier: "",
        signed_ip: Keyword.get(opts, :ip, ""),
        signed_protocol: Keyword.get(opts, :protocol, ""),
        signed_version: version,
        signed_resource: resource,
        signed_snapshot_time: "",
        signed_encryption_scope: "",
        rscc: "",
        rscd: "",
        rsce: "",
        rscl: "",
        rsct: ""
      ]

      with {:ok, sig} <- hmac_base64(credential.key, string_to_sign(fields)) do
        %{"sv" => version, "sr" => resource, "sp" => permissions, "se" => expiry, "sig" => sig}
        |> put_optional_params(start, opts)
        |> finish_sas(opts)
      end
    end
  end

  defp put_optional_params(params, start, opts) do
    params
    |> put_param("st", start)
    |> put_param("sip", Keyword.get(opts, :ip))
    |> put_param("spr", Keyword.get(opts, :protocol))
  end

  defp put_param(params, _key, value) when value in [nil, ""], do: params
  defp put_param(params, key, value), do: Map.put(params, key, value)

  defp finish_sas(params, opts) do
    if Keyword.get(opts, :as_credential, false) do
      {:ok, SASCredential.new(params)}
    else
      {:ok, URI.encode_query(params)}
    end
  end

  defp normalize_permissions(permissions) when is_binary(permissions) do
    chars = String.to_charlist(permissions)

    case chars -- @permission_order do
      [] ->
        {:ok, @permission_order |> Enum.filter(&(&1 in chars)) |> List.to_string()}

      unknown ->
        {:error,
         Error.new(
           code: "InvalidArgument",
           message: "Unknown SAS permission(s): #{inspect(List.to_string(unknown))}",
           service: :blob
         )}
    end
  end

  defp hmac_base64(key_b64, string) do
    case Base.decode64(key_b64) do
      {:ok, key} when key != "" ->
        {:ok, Base.encode64(:crypto.mac(:hmac, :sha256, key, string))}

      _ ->
        {:error,
         Error.new(
           code: "InvalidCredential",
           message: "SAS signing key is empty or not valid Base64",
           service: :blob
         )}
    end
  end

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Operation.iso8601_utc(dt)

  @udk_fields [
    signed_oid: "SignedOid",
    signed_tid: "SignedTid",
    signed_start: "SignedStart",
    signed_expiry: "SignedExpiry",
    signed_service: "SignedService",
    signed_version: "SignedVersion",
    value: "Value"
  ]

  defp parse_user_delegation_key(xml) do
    import SweetXml

    udk = Map.new(@udk_fields, fn {key, tag} -> {key, xpath(xml, ~x"//#{tag}/text()"s)} end)

    case Enum.filter(@udk_fields, fn {key, _tag} -> udk[key] == "" end) do
      [] -> {:ok, udk}
      missing -> {:error, invalid_udk("missing #{Enum.map_join(missing, ", ", &elem(&1, 1))}")}
    end
  catch
    :exit, reason -> {:error, invalid_udk("not XML: #{inspect(reason)}")}
  end

  defp invalid_udk(detail) do
    Error.new(
      code: "InvalidResponse",
      message: "User delegation key response is invalid (#{detail})",
      service: :blob
    )
  end
end
