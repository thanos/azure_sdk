defmodule AzureSDK.Storage.Blob.LeaseTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Storage.Blob.Lease

  defp expect_lease(bypass, fun) do
    Bypass.expect(bypass, "PUT", AzureMock.path(["uploads", "a.txt"]), fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["comp"] == "lease"
      fun.(conn)
    end)
  end

  test "acquires a lease", %{bypass: bypass, client: client} do
    expect_lease(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-action") == ["acquire"]

      conn
      |> Plug.Conn.put_resp_header("x-ms-lease-id", "lease-123")
      |> Plug.Conn.resp(201, "")
    end)

    assert {:ok, "lease-123"} =
             Lease.acquire(client, "uploads", "a.txt",
               duration: 30,
               proposed_lease_id: "lease-123"
             )
  end

  test "renews a lease", %{bypass: bypass, client: client} do
    expect_lease(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-action") == ["renew"]

      conn
      |> Plug.Conn.put_resp_header("x-ms-lease-id", "lease-123")
      |> Plug.Conn.resp(200, "")
    end)

    assert {:ok, "lease-123"} =
             Lease.renew(client, "uploads", "a.txt", lease_id: "lease-123")
  end

  test "changes a lease", %{bypass: bypass, client: client} do
    expect_lease(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-action") == ["change"]

      conn
      |> Plug.Conn.put_resp_header("x-ms-lease-id", "lease-new")
      |> Plug.Conn.resp(200, "")
    end)

    assert {:ok, "lease-new"} =
             Lease.change(client, "uploads", "a.txt",
               lease_id: "lease-old",
               proposed_lease_id: "lease-new"
             )
  end

  test "releases a lease", %{bypass: bypass, client: client} do
    expect_lease(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-action") == ["release"]
      Plug.Conn.resp(conn, 200, "")
    end)

    assert {:ok, :released} =
             Lease.release(client, "uploads", "a.txt", lease_id: "lease-123")
  end

  test "breaks a lease", %{bypass: bypass, client: client} do
    expect_lease(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-action") == ["break"]
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-break-period") == ["15"]
      Plug.Conn.resp(conn, 202, "")
    end)

    assert {:ok, :broken} =
             Lease.break(client, "uploads", "a.txt", break_period: 15)
  end

  test "returns error on lease failure", %{bypass: bypass, client: client} do
    AzureMock.stub_error(
      bypass,
      "PUT",
      AzureMock.path(["uploads", "a.txt"]),
      409,
      "LeaseAlreadyPresent",
      "lease exists"
    )

    assert {:error, %{status: 409, code: "LeaseAlreadyPresent"}} =
             Lease.acquire(client, "uploads", "a.txt")
  end
end
