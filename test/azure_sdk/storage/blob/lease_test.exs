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

  describe "retries" do
    @retry %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false}

    # Fails the first request with a transport error, then answers 201, and
    # reports each request's lease headers to the test process.
    defp flaky_client(test_pid) do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        send(test_pid, {:lease_request, Map.new(conn.req_headers)})

        case Agent.get_and_update(calls, &{&1, &1 + 1}) do
          0 -> Req.Test.transport_error(conn, :closed)
          _ -> Plug.Conn.resp(conn, 201, "")
        end
      end

      AzureSDK.Storage.Client.new(
        account: AzureMock.account(),
        credential: AzureMock.credential(),
        endpoint: "http://localhost/#{AzureMock.account()}",
        retry: @retry,
        req_options: [plug: plug]
      )
    end

    test "acquire generates a proposed lease id and a retry reuses it" do
      client = flaky_client(self())

      assert {:ok, lease_id} = Lease.acquire(client, "uploads", "a.txt")

      assert lease_id =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      assert_received {:lease_request, %{"x-ms-proposed-lease-id" => ^lease_id}}
      assert_received {:lease_request, %{"x-ms-proposed-lease-id" => ^lease_id}}
    end

    test "change is not retried" do
      client = flaky_client(self())

      assert {:error, %AzureSDK.Error{}} =
               Lease.change(client, "uploads", "a.txt", lease_id: "old", proposed_lease_id: "new")

      assert_received {:lease_request, %{"x-ms-lease-action" => "change"}}
      refute_received {:lease_request, _}
    end
  end

  describe "missing options" do
    test "return InvalidArgument instead of raising", %{client: client} do
      assert {:error, %AzureSDK.Error{code: "InvalidArgument"}} =
               Lease.renew(client, "uploads", "a.txt")

      assert {:error, %AzureSDK.Error{code: "InvalidArgument"}} =
               Lease.release(client, "uploads", "a.txt", [])

      assert {:error, %AzureSDK.Error{code: "InvalidArgument", message: message}} =
               Lease.change(client, "uploads", "a.txt", lease_id: "old")

      assert message =~ ":proposed_lease_id"
    end
  end
end
