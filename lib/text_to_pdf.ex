defmodule TextToPdf do
  @moduledoc """
  A minimal custom module to convert plain text to a simple PDF.
  """

  @font_object """
  2 0 obj
  << /Type /Font
     /Subtype /Type1
     /Name /F1
     /BaseFont /Helvetica
     /Encoding /WinAnsiEncoding
  >>
  endobj
  """

  def generate_pdf(text, filename \\ "output.pdf") do
    File.mkdir_p!(Path.dirname(filename))
    content_stream = "BT /F1 12 Tf 50 750 Td (#{escape_text(text)}) Tj ET"

    content = """
    1 0 obj
    << /Length #{byte_size(content_stream)} >>
    stream
    #{content_stream}
    endstream
    endobj
    """

    objects = [
      %{id: 1, content: content},
      %{id: 2, content: @font_object},
      %{id: 3, content: """
      3 0 obj
      << /Type /Page
         /Parent 4 0 R
         /MediaBox [0 0 595 842]
         /Contents 1 0 R
         /Resources << /Font << /F1 2 0 R >> >>
      >>
      endobj
      """},
      %{id: 4, content: """
      4 0 obj
      << /Type /Pages
         /Kids [3 0 R]
         /Count 1
      >>
      endobj
      """},
      %{id: 5, content: """
      5 0 obj
      << /Type /Catalog
         /Pages 4 0 R
      >>
      endobj
      """}
    ]

    {body, xrefs} = build_objects(objects, 9)

    xref_table = """
    xref
    0 #{length(xrefs) + 1}
    0000000000 65535 f
    #{Enum.join(xrefs, "\n")}
    """

    trailer = """
    trailer
    << /Root 5 0 R
       /Size #{length(xrefs) + 1}
    >>
    startxref
    #{byte_size(body)}
    %%EOF
    """

    pdf = """
    %PDF-1.4
    #{body}
    #{xref_table}
    #{trailer}
    """

    File.write!(filename, pdf)
    {:ok, filename}
  end

  defp escape_text(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

  defp build_objects(objects, start_id) do
    Enum.reduce(objects, {"", [], 0}, fn obj, {acc, xrefs, offset} ->
      obj_text = obj.content
      new_acc = acc <> obj_text <> "\n"
      new_xrefs = xrefs ++ [String.pad_leading("#{offset}", 10, "0") <> " 00000 n "]
      {new_acc, new_xrefs, offset + byte_size(obj_text <> "\n")}
    end)
    |> then(fn {body, xrefs, _} -> {body, xrefs} end)
  end
end
