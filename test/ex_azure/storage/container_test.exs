defmodule ExAzure.Storage.ContainerTest do
  use ExAzure.AzureMockCase, async: true

  alias ExAzure.Storage.Container

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

  test "returns container metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_head_container(bypass, "uploads", %{"owner" => "team"})

    assert {:ok, %{"owner" => "team"}} = Container.metadata(client, "uploads")
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
