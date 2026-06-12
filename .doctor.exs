%Doctor.Config{
  min_module_doc_coverage: 80,
  min_module_spec_coverage: 50,
  min_overall_doc_coverage: 80,
  min_overall_spec_coverage: 50,
  ignore_modules: [
    ExAzure.Identity.Credential,
    ExAzure.Integrations.Broadway,
    ExAzure.Integrations.Explorer,
    ExAzure.Integrations.Flow,
    ExAzure.Integrations.Livebook,
    ExAzure.Integrations.Nx,
    ExAzure.Management.Network,
    ExAzure.Management.Policy,
    ExAzure.Management.Replication,
    ExAzure.Management.StorageAccount,
    ExAzure.Storage.DataLake,
    ExAzure.Storage.FileShare,
    ExAzure.Storage.Queue,
    ExAzure.Storage.Table
  ]
}
