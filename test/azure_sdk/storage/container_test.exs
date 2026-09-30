defmodule AzureSDK.Storage.ContainerTest do
  use AzureSDK.AzureMockCase, async: true

  @no_retry %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false}

  alias AzureSDK.Storage.Container

  test "creates a container", %{bypass: bypass, client: client} do
    AzureMock.stub_put_container(bypass, "uploads")

    assert {:ok, %{name: "uploads"}} = Container.create(client, "uploads")
  end

  test "creates a container with metadata and public access", %{bypass: bypass, client: client} do
    AzureMock.stub_put_container(bypass, "public")

    assert {:ok, %{name: "public", metadata: %{"env" => "test"}}} =
             Container.create(client, "public",
               public_access: "container",
               metadata: %{"env" => "test"}
             )
  end

  test "deletes a container", %{bypass: bypass, client: client} do
    AzureMock.stub_delete_container(bypass, "uploads")

    assert {:ok, :deleted} = Container.delete(client, "uploads")
  end

  test "ignores unknown opts on delete", %{bypass: bypass, client: client} do
    AzureMock.stub_delete_container(bypass, "uploads")

    assert {:ok, :deleted} = Container.delete(client, "uploads", metadata: %{"a" => "b"})
  end

  test "lists containers", %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers(bypass, ["a", "b"])

    assert {:ok, containers} = Container.list(client)
    assert Enum.map(containers, & &1.name) == ["a", "b"]
  end

  test "lists containers across pages", %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers_paginated(bypass, [
      %{containers: ["a"], marker: "page-2"},
      %{containers: ["b"], marker: nil}
    ])

    assert {:ok, containers} = Container.list(client)
    assert Enum.map(containers, & &1.name) == ["a", "b"]
  end

  test "returns empty list for invalid list xml", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "GET", AzureMock.path([]), fn conn ->
      Plug.Conn.resp(conn, 200, "")
    end)

    assert {:ok, []} = Container.list(client)
  end

  test "lists blobs in a container", %{bypass: bypass, client: client} do
    AzureMock.stub_list_blobs(bypass, "uploads", ["a.txt", "b.txt"])

    assert {:ok, blobs} = Container.list_blobs(client, "uploads")
    assert Enum.map(blobs, & &1.name) == ["a.txt", "b.txt"]
  end

  test "list_page returns a single page", %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers(bypass, ["only"])

    assert {:ok, %{items: [%{name: "only"}], marker: nil}} =
             Container.list_page(client, max_results: 5, prefix: "o")
  end

  test "list_stream enumerates containers", %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers_paginated(bypass, [
      %{containers: ["a"], marker: "next"},
      %{containers: ["b"], marker: nil}
    ])

    assert Enum.map(Container.list_stream(client), & &1.name) == ["a", "b"]
  end

  test "list_blobs_page and list_blobs_stream", %{bypass: bypass, client: client} do
    AzureMock.stub_list_blobs(bypass, "uploads", ["a.txt"])

    assert {:ok, %{items: [%{name: "a.txt"}], marker: nil}} =
             Container.list_blobs_page(client, "uploads", max_results: 10, prefix: "a")

    assert Enum.map(Container.list_blobs_stream(client, "uploads"), & &1.name) == ["a.txt"]
  end

  test "list keeps page order across three pages",
       %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers_paginated(bypass, [
      %{containers: ["a", "b"], marker: "page-2"},
      %{containers: ["c"], marker: "page-3"},
      %{containers: ["d"], marker: nil}
    ])

    assert {:ok, containers} = Container.list(client, max_results: 2)
    assert Enum.map(containers, & &1.name) == ["a", "b", "c", "d"]
  end

  test "list_stream raises StreamError when a later page fails", %{bypass: bypass} do
    client = AzureMock.client(bypass, retry: @no_retry)
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "GET", AzureMock.path([]), fn conn ->
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> Plug.Conn.resp(conn, 200, list_containers_xml(["a"], "next"))
        _ -> Plug.Conn.resp(conn, 500, "")
      end
    end)

    stream = Container.list_stream(client)

    assert %Container.StreamError{reason: %AzureSDK.Error{status: 500}} =
             assert_raise(Container.StreamError, fn -> Enum.to_list(stream) end)
  end

  test "list_blobs_stream raises StreamError when a page fails", %{bypass: bypass} do
    client = AzureMock.client(bypass, retry: @no_retry)

    Bypass.expect(bypass, "GET", AzureMock.path(["uploads"]), fn conn ->
      Plug.Conn.resp(conn, 500, "")
    end)

    assert_raise Container.StreamError, fn ->
      client |> Container.list_blobs_stream("uploads") |> Enum.to_list()
    end
  end

  test "returns container metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_head_container(bypass, "uploads", %{"owner" => "team"})

    assert {:ok, %{"owner" => "team"}} = Container.metadata(client, "uploads")
  end

  test "exists? returns true when container is present", %{bypass: bypass, client: client} do
    AzureMock.stub_head_container(bypass, "uploads")

    assert Container.exists?(client, "uploads") == true
  end

  test "exists? returns false when container is missing", %{
    bypass: bypass,
    client: client,
    account: account
  } do
    AzureMock.stub_error(
      bypass,
      "HEAD",
      AzureMock.path(["missing"], account),
      404,
      "ContainerNotFound",
      "The specified container does not exist."
    )

    assert Container.exists?(client, "missing") == false
  end

  test "exists? propagates non-404 errors", %{bypass: bypass, client: client, account: account} do
    AzureMock.stub_error(
      bypass,
      "HEAD",
      AzureMock.path(["uploads"], account),
      403,
      "AuthorizationFailure",
      "Forbidden"
    )

    assert {:error, %{status: 403}} = Container.exists?(client, "uploads")
  end

  test "returns azure error on failure", %{bypass: bypass, client: client, account: account} do
    AzureMock.stub_error(
      bypass,
      "PUT",
      AzureMock.path(["missing"], account),
      404,
      "ContainerNotFound",
      "The specified container does not exist."
    )

    assert {:error, %{code: "ContainerNotFound", status: 404, service: :blob}} =
             Container.create(client, "missing")
  end

  defp list_containers_xml(names, marker) do
    entries =
      Enum.map_join(
        names,
        "",
        &"<Container><Name>#{&1}</Name><Properties></Properties></Container>"
      )

    ~s(<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Containers>#{entries}</Containers><NextMarker>#{marker}</NextMarker></EnumerationResults>)
  end
end
