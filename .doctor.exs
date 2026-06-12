%Doctor.Config{
  min_module_doc_coverage: 80,
  min_module_spec_coverage: 50,
  min_overall_doc_coverage: 80,
  min_overall_spec_coverage: 50,
  ignore_modules: [
    AzureSDK.Identity.Credential,
    AzureSDK.Integrations.Broadway,
    AzureSDK.Integrations.Explorer,
    AzureSDK.Integrations.Flow,
    AzureSDK.Integrations.Livebook,
    AzureSDK.Integrations.Nx,
    AzureSDK.Management.Network,
    AzureSDK.Management.Policy,
    AzureSDK.Management.Replication,
    AzureSDK.Management.StorageAccount,
    AzureSDK.Storage.DataLake,
    AzureSDK.Storage.FileShare,
    AzureSDK.Storage.Queue,
    AzureSDK.Storage.Table
  ]
}
