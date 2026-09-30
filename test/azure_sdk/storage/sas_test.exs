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

  describe "known answers" do
    # Signatures below were produced by the Azure SDK for Python 12.30.3
    # (generate_blob_sas / generate_container_sas) with the same key, times and
    # service version 2024-11-04.
    test "blob service SAS matches the reference signature" do
      cred = SharedKeyCredential.new("acct", @key)

      assert {:ok, query} =
               Sas.sign_blob(cred,
                 container: "c",
                 blob: "b.txt",
                 permissions: "r",
                 start: ~U[2029-01-01 00:00:00Z],
                 expiry: ~U[2030-01-01 00:00:00Z],
                 ip: "127.0.0.1",
                 protocol: "https",
                 api_version: "2024-11-04"
               )

      assert URI.decode_query(query)["sig"] == "ar8E0OZwD5lEY9rCSRloM3VAn7e87CWtle86/5Mrlow="
    end

    test "container service SAS matches the reference signature" do
      cred = SharedKeyCredential.new("acct", @key)

      assert {:ok, query} =
               Sas.sign_container(cred,
                 container: "c",
                 permissions: "rl",
                 expiry: ~U[2030-01-01 00:00:00Z],
                 api_version: "2024-11-04"
               )

      assert URI.decode_query(query)["sig"] == "YELizh0fDvtcSNrTfRIq1332V8YZqGHDFfY01X2gnXI="
    end

    test "user-delegation SAS signs the 24-field 2020-12-06 string-to-sign" do
      # One line per field, in the documented order for versions 2020-12-06+.
      expected_string_to_sign =
        Enum.join(
          [
            "r",
            "2029-01-01T00:00:00Z",
            "2030-01-01T00:00:00Z",
            "/blob/acct/c/b.txt",
            "oid",
            "tid",
            "2029-01-01T00:00:00Z",
            "2030-01-01T00:00:00Z",
            "b",
            "2024-11-04",
            # signedAuthorizedUserObjectId, signedUnauthorizedUserObjectId, signedCorrelationId
            "",
            "",
            "",
            # signedIP, signedProtocol, signedVersion, signedResource
            "",
            "https",
            "2024-11-04",
            "b",
            # signedSnapshotTime, signedEncryptionScope, rscc, rscd, rsce, rscl, rsct
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

      expected_sig =
        Base.encode64(:crypto.mac(:hmac, :sha256, Base.decode64!(@key), expected_string_to_sign))

      assert {:ok, query} =
               Sas.sign_user_delegation_blob(udk(),
                 account: "acct",
                 container: "c",
                 blob: "b.txt",
                 permissions: "r",
                 start: ~U[2029-01-01 00:00:00Z],
                 expiry: ~U[2030-01-01 00:00:00Z],
                 protocol: "https",
                 api_version: "2024-11-04"
               )

      assert URI.decode_query(query)["sig"] == expected_sig
    end
  end

  describe "input handling" do
    test "permissions are normalized to the service order" do
      cred = SharedKeyCredential.new("acct", @key)

      {:ok, query} =
        Sas.sign_blob(cred,
          container: "c",
          blob: "b",
          permissions: "wr",
          expiry: ~U[2030-01-01 00:00:00Z]
        )

      {:ok, reference} =
        Sas.sign_blob(cred,
          container: "c",
          blob: "b",
          permissions: "rw",
          expiry: ~U[2030-01-01 00:00:00Z]
        )

      assert URI.decode_query(query)["sp"] == "rw"
      assert query == reference
    end

    test "unknown permission letters are rejected" do
      cred = SharedKeyCredential.new("acct", @key)

      assert {:error, %{code: "InvalidArgument", message: message}} =
               Sas.sign_blob(cred,
                 container: "c",
                 blob: "b",
                 permissions: "rz",
                 expiry: ~U[2030-01-01 00:00:00Z]
               )

      assert message =~ "z"
    end

    test "non-UTC times are signed as UTC" do
      cred = SharedKeyCredential.new("acct", @key)

      athens = %DateTime{
        year: 2030,
        month: 1,
        day: 1,
        hour: 2,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        time_zone: "Europe/Athens",
        zone_abbr: "EET",
        utc_offset: 7200,
        std_offset: 0
      }

      {:ok, query} =
        Sas.sign_blob(cred, container: "c", blob: "b", permissions: "r", expiry: athens)

      {:ok, reference} =
        Sas.sign_blob(cred,
          container: "c",
          blob: "b",
          permissions: "r",
          expiry: ~U[2030-01-01 00:00:00Z]
        )

      assert URI.decode_query(query)["se"] == "2030-01-01T00:00:00Z"
      assert query == reference
    end

    test "missing required options return InvalidArgument" do
      cred = SharedKeyCredential.new("acct", @key)

      assert {:error, %{code: "InvalidArgument", message: message}} =
               Sas.sign_blob(cred, container: "c", permissions: "r")

      assert message =~ ":blob"
      assert message =~ ":expiry"

      assert {:error, %{code: "InvalidArgument"}} = Sas.sign_container(cred, [])

      assert {:error, %{code: "InvalidArgument"}} =
               Sas.sign_user_delegation_blob(udk(), account: "acct")
    end
  end

  describe "get_user_delegation_key/2 response validation" do
    for {label, body} <- [
          {"an empty body", ""},
          {"a body that is not XML", "not xml"},
          {"a key without Value",
           "<UserDelegationKey><SignedOid>oid</SignedOid></UserDelegationKey>"}
        ] do
      test "returns InvalidResponse for #{label}", %{bypass: bypass, client: client} do
        body = unquote(body)

        Bypass.expect(bypass, "POST", AzureMock.path([]), fn conn ->
          Plug.Conn.resp(conn, 200, body)
        end)

        assert {:error, %{code: "InvalidResponse"}} =
                 Sas.get_user_delegation_key(client, expiry: ~U[2030-01-01 00:00:00Z])
      end
    end

    test "requires :expiry", %{client: client} do
      assert {:error, %{code: "InvalidArgument"}} = Sas.get_user_delegation_key(client, [])
    end
  end

  defp udk do
    %{
      signed_oid: "oid",
      signed_tid: "tid",
      signed_start: "2029-01-01T00:00:00Z",
      signed_expiry: "2030-01-01T00:00:00Z",
      signed_service: "b",
      signed_version: "2024-11-04",
      value: @key
    }
  end
end
