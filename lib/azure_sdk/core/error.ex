defmodule AzureSDK.Error do
  @moduledoc """
  Standardized, pattern-match friendly error struct for all AzureSDK operations.

  All public APIs return `{:ok, result}` or `{:error, %AzureSDK.Error{}}`.
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
  Creates a new error struct.
  """
  @spec new(keyword()) :: t()
  def new(fields) do
    struct!(__MODULE__, fields)
  end

  @doc """
  Builds an error from an HTTP response body and headers.
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
