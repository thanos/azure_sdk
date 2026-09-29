defmodule AzureSDK.Error do
  @moduledoc """
  Standardized error returned by AzureSDK public APIs.

  Callers should pattern match on `{:error, %AzureSDK.Error{}}`. This module
  never raises for Azure HTTP failures; transport exceptions are wrapped via
  `from_exception/2`.

  ## Fields

  * `:status` - HTTP status when the failure came from a response, otherwise `nil`
  * `:code` - Azure error code (for example `"ContainerNotFound"`), when present
  * `:message` - human-readable description
  * `:request_id` - value of `x-ms-request-id` when available
  * `:service` - logical service atom (`:blob`, `:identity`, …)
  * `:details` - extra parsed fields from an error XML/JSON body
  * `:cause` - original exception or reason for transport failures

  ## Examples

      iex> error = AzureSDK.Error.new(status: 404, code: "ContainerNotFound", service: :blob)
      iex> match?(%AzureSDK.Error{status: 404}, error)
      true
  """

  @typedoc """
  Error struct. See the module documentation for field meanings.
  """
  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t() | nil,
          message: String.t() | nil,
          request_id: String.t() | nil,
          service: atom() | nil,
          details: map() | nil,
          cause: term() | nil
        }

  defstruct [:status, :code, :message, :request_id, :service, :details, :cause]

  @doc """
  Creates a new error struct from keyword fields.

  Unknown keys raise `KeyError` via `struct!/2`.

  ## Examples

      iex> AzureSDK.Error.new(message: "boom", service: :blob)
      %AzureSDK.Error{message: "boom", service: :blob, status: nil, code: nil,
       request_id: nil, details: nil, cause: nil}
  """
  @spec new(keyword()) :: t()
  def new(fields) when is_list(fields) do
    struct!(__MODULE__, fields)
  end

  @doc """
  Builds an error from an HTTP response body and headers.

  ## Parameters

  * `service` - service atom stored on the error
  * `status` - HTTP status code
  * `headers` - response headers (string keys; lookup is case-insensitive for `x-ms-request-id`)
  * `body` - response body, often Azure error XML; may be `nil` or empty

  ## Returns

  Always returns `%AzureSDK.Error{}`. When the body is not XML, `:code` may be
  `nil` and `:message` falls back to a short status phrase.

  ## Examples

      iex> body = ~s(<?xml version="1.0"?><Error><Code>BlobNotFound</Code><Message>missing</Message></Error>)
      iex> error = AzureSDK.Error.from_response(:blob, 404, %{"x-ms-request-id" => "abc"}, body)
      iex> {error.status, error.code, error.request_id}
      {404, "BlobNotFound", "abc"}
  """
  @spec from_response(atom(), non_neg_integer(), map(), binary() | nil) :: t()
  def from_response(service, status, headers, body) do
    parsed = AzureSDK.Core.Xml.Error.parse(body)

    %__MODULE__{
      status: status,
      code: parsed[:code],
      message: parsed[:message] || default_message(status),
      request_id: header_value(headers, "x-ms-request-id"),
      service: service,
      details: parsed[:details]
    }
  end

  @doc """
  Builds an error from a transport-level exception or reason.

  ## Parameters

  * `service` - service atom stored on the error
  * `reason` - exception struct or any term; stored in `:cause`

  ## Returns

  `%AzureSDK.Error{message: …, service: …, cause: reason}` with no HTTP status.

  ## Examples

      iex> error = AzureSDK.Error.from_exception(:blob, :timeout)
      iex> error.message
      ":timeout"
      iex> error.cause
      :timeout
  """
  @spec from_exception(atom(), term()) :: t()
  def from_exception(service, reason) do
    %__MODULE__{
      message: exception_message(reason),
      service: service,
      cause: reason
    }
  end

  defp exception_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp exception_message(reason), do: inspect(reason)

  defp header_value(headers, name) when is_map(headers) do
    headers
    |> Enum.find_value(fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == name, do: value

      _ ->
        nil
    end)
  end

  defp header_value(_, _), do: nil

  defp default_message(404), do: "Not Found"
  defp default_message(403), do: "Forbidden"
  defp default_message(401), do: "Unauthorized"
  defp default_message(status), do: "HTTP #{status}"
end
