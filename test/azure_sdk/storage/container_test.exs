defmodule AzureSDK.Storage.ContainerTest do
  use AzureSDK.AzureMockCase, async: true

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
end
