defmodule ExAzure.Core.XmlTest do
  use ExUnit.Case, async: true

  alias ExAzure.Core.Xml.{Error, ListBlobs, ListContainers}

  test "parses error xml" do
    xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <Error>
      <Code>ContainerNotFound</Code>
      <Message>The specified container does not exist.</Message>
    </Error>
    """

    assert %{code: "ContainerNotFound", message: "The specified container does not exist."} =
             Error.parse(xml)
  end

  test "parses list containers xml" do
    xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <EnumerationResults>
      <Containers>
        <Container>
          <Name>uploads</Name>
          <Properties>
            <Last-Modified>Wed, 01 Jan 2025 00:00:00 GMT</Last-Modified>
            <Etag>\"0x8D\"</Etag>
          </Properties>
        </Container>
      </Containers>
    </EnumerationResults>
    """

    assert [%{name: "uploads"}] = ListContainers.parse(xml)
  end

  test "parses list blobs xml" do
    xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <EnumerationResults>
      <Blobs>
        <Blob>
          <Name>file.txt</Name>
          <Properties>
            <Content-Length>5</Content-Length>
            <Content-Type>text/plain</Content-Type>
          </Properties>
        </Blob>
      </Blobs>
    </EnumerationResults>
    """

    assert [%{name: "file.txt", properties: %{content_length: 5}}] = ListBlobs.parse(xml)
  end
end
