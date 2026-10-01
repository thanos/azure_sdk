defmodule AzureSDK.DoctestTest do
  use ExUnit.Case, async: false

  doctest AzureSDK
  doctest AzureSDK.Error
  doctest AzureSDK.Core.Client
  doctest AzureSDK.Core.Request
  doctest AzureSDK.Core.Response
  doctest AzureSDK.Core.Retry
  doctest AzureSDK.Core.Telemetry
  doctest AzureSDK.Identity.AccessToken
  doctest AzureSDK.Identity.TokenCredential
  doctest AzureSDK.Identity.SharedKeyCredential
  doctest AzureSDK.Identity.SASCredential
  doctest AzureSDK.Identity.ClientSecretCredential
  doctest AzureSDK.Identity.ManagedIdentityCredential
  doctest AzureSDK.Identity.EnvironmentCredential
  doctest AzureSDK.Identity.DefaultAzureCredential
  doctest AzureSDK.Identity.WorkloadIdentityCredential
  doctest AzureSDK.Identity.TokenCache
  doctest AzureSDK.Pipeline.Bearer
  doctest AzureSDK.Storage.Client
  doctest AzureSDK.Storage.ServiceVersion
  doctest AzureSDK.Storage.Path
  doctest AzureSDK.Storage.Metadata
  doctest AzureSDK.Storage.Conditions
  doctest AzureSDK.Storage.Blob.Block
  doctest AzureSDK.Storage.Sas
  doctest AzureSDK.Storage.Queue
  doctest AzureSDK.Storage.Queue.Message
  doctest AzureSDK.Storage.Queue.StreamError
  doctest AzureSDK.Core.Xml.ListQueues
  doctest AzureSDK.Core.Xml.QueueMessages
end
