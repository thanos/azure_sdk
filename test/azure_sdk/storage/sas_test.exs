defmodule AzureSDK.Storage.SasTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Identity.{SASCredential, SharedKeyCredential}
  alias AzureSDK.Storage.Sas

  @key Base.encode64("sixteen-byte-key!")

  test "signs a blob service SAS query string" do
    cred = SharedKeyCredential.new("acct", @key)

    assert {:ok, query} =
             Sas.sign_blob(cred,
               container: "c",
               blob: "b.txt",
               permissions: "r",
               expiry: ~U[2030-01-01 00:00:00Z],
               start: ~U[2029-01-01 00:00:00Z],
               ip: "127.0.0.1",
               protocol: "https"
             )

    params = URI.decode_query(query)
    assert params["sp"] == "r"
    assert params["sr"] == "b"
    assert params["st"]
    assert params["sip"] == "127.0.0.1"
    assert params["spr"] == "https"
    assert params["sig"]
  end

  test "returns a SASCredential when requested" do
    cred = SharedKeyCredential.new("acct", @key)

    assert {:ok, %SASCredential{params: params}} =
             Sas.sign_container(cred,
               container: "c",
               permissions: "rl",
               expiry: ~U[2030-01-01 00:00:00Z],
               as_credential: true
             )

    assert params["sr"] == "c"
  end

  test "returns InvalidCredential for a bad shared key" do
    cred = SharedKeyCredential.new("acct", "not-base64!!!")

    assert {:error, %{code: "InvalidCredential"}} =
             Sas.sign_blob(cred,
               container: "c",
               blob: "b.txt",
               permissions: "r",
               expiry: ~U[2030-01-01 00:00:00Z]
             )
  end

  test "fetches a user delegation key", %{bypass: bypass, client: client} do
    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <UserDelegationKey>
      <SignedOid>oid</SignedOid>
      <SignedTid>tid</SignedTid>
      <SignedStart>2029-01-01T00:00:00Z</SignedStart>
      <SignedExpiry>2030-01-01T00:00:00Z</SignedExpiry>
      <SignedService>b</SignedService>
      <SignedVersion>2024-11-04</SignedVersion>
      <Value>#{@key}</Value>
    </UserDelegationKey>
    """

    Bypass.expect(bypass, "POST", AzureMock.path([]), fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["comp"] == "userdelegationkey"
      Plug.Conn.resp(conn, 200, body)
    end)

    assert {:ok, udk} =
             Sas.get_user_delegation_key(client, expiry: ~U[2030-01-01 00:00:00Z])

    assert udk.signed_oid == "oid"
    assert udk.value == @key
  end

  test "signs a user-delegation blob SAS" do
    udk = %{
      signed_oid: "oid",
      signed_tid: "tid",
      signed_start: "2029-01-01T00:00:00Z",
      signed_expiry: "2030-01-01T00:00:00Z",
      signed_service: "b",
      signed_version: "2024-11-04",
      value: @key
    }

    assert {:ok, query} =
             Sas.sign_user_delegation_blob(udk,
               account: "acct",
               container: "c",
               blob: "b.txt",
               permissions: "r",
               expiry: ~U[2030-01-01 00:00:00Z],
               start: ~U[2029-06-01 00:00:00Z],
               protocol: "https"
             )

    params = URI.decode_query(query)
    assert params["skoid"] == "oid"
    assert params["sig"]
    assert params["spr"] == "https"
  end

  test "user-delegation signing fails for bad key material" do
    udk = %{
      signed_oid: "oid",
      signed_tid: "tid",
      signed_start: "2029-01-01T00:00:00Z",
      signed_expiry: "2030-01-01T00:00:00Z",
      signed_service: "b",
      signed_version: "2024-11-04",
      value: "%%%"
    }

    assert {:error, %{code: "InvalidCredential"}} =
             Sas.sign_user_delegation_blob(udk,
               account: "acct",
               container: "c",
               blob: "b.txt",
               permissions: "r",
               expiry: ~U[2030-01-01 00:00:00Z]
             )
  end
end
