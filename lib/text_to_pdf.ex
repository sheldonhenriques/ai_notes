defmodule TextToPdf do
  @moduledoc """
  A minimal, dependency-free text-to-PDF generator for Elixir.
  Supports multi-line and multi-page plain text PDFs.
  """

  @page_width 595
  @page_height 842
  @start_y 750
  @line_height 14
  @left_margin 50
  @right_margin 50
  @bottom_margin 50
  @top_margin 50
  @max_line_width @page_width - @left_margin - @right_margin
  @avg_char_width 5.5  # Better fit than 6 for Helvetica 12pt
  @chars_per_line div(@max_line_width, @avg_char_width |> round)
  @lines_per_page div(@start_y - @bottom_margin, @line_height)

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

    # Process text: split into lines and handle word wrapping
    # Don't reject empty lines - they represent intentional blank lines
    lines =
      text
      |> String.split("\n")
      |> Enum.flat_map(&wrap_line/1)

    pages = Enum.chunk_every(lines, @lines_per_page)

    # Generate PDF stream objects for each page's text
    {content_objs, content_ids} =
      pages
      |> Enum.with_index()
      |> Enum.map(fn {page_lines, page_index} ->
        content_stream = generate_page_content(page_lines)
        id = 10 + page_index

        content_obj = %{
          id: id,
          content: """
          #{id} 0 obj
          << /Length #{byte_size(content_stream)} >>
          stream
          #{content_stream}
          endstream
          endobj
          """
        }

        {content_obj, id}
      end)
      |> Enum.unzip()

    # Generate page objects referencing the content stream
    {page_objs, page_ids} =
      content_ids
      |> Enum.with_index()
      |> Enum.map(fn {content_id, page_index} ->
        page_id = 20 + page_index

        page_obj = %{
          id: page_id,
          content: """
          #{page_id} 0 obj
          << /Type /Page
             /Parent 4 0 R
             /MediaBox [0 0 #{@page_width} #{@page_height}]
             /Contents #{content_id} 0 R
             /Resources << /Font << /F1 2 0 R >> >>
          >>
          endobj
          """
        }

        {page_obj, page_id}
      end)
      |> Enum.unzip()

    # Static PDF catalog and page tree
    catalog_objs = [
      %{id: 1, content: "1 0 obj\n<< >>\nendobj\n"}, # Placeholder object
      %{id: 2, content: @font_object},
      %{id: 4, content: """
      4 0 obj
      << /Type /Pages
         /Kids [#{Enum.map_join(page_ids, " ", &"#{&1} 0 R")}]
         /Count #{length(page_ids)}
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

    all_objs = catalog_objs ++ content_objs ++ page_objs
    all_objs = Enum.sort_by(all_objs, & &1.id)

    {body, xrefs} = build_objects(all_objs)

    xref_offset = byte_size(body)

    trailer = """
    xref
    0 #{length(xrefs)}
    #{Enum.join(xrefs, "")}
    trailer
    << /Root 5 0 R
       /Size #{length(xrefs)}
    >>
    startxref
    #{xref_offset}
    %%EOF
    """

    pdf = "%PDF-1.4\n" <> body <> trailer
    {:ok, pdf}
  end

  defp wrap_line(""), do: [%{text: "", indent: 0}]

  defp wrap_line(line) do
    indent = count_leading_spaces(line)
    words = String.trim_leading(line) |> String.split(" ")
    wrapped_lines = do_wrap(words, [], "", [])

    Enum.map(wrapped_lines, fn l -> %{text: l, indent: indent} end)
  end

  defp do_wrap([], _acc, curr_line, result) do
    Enum.reverse([curr_line | result])
  end

  defp do_wrap([word | rest], _acc, curr_line, result) do
    new_line = if curr_line == "", do: word, else: curr_line <> " " <> word
    est_width = estimate_width(new_line)

    if est_width > @max_line_width do
      do_wrap([word | rest], [], "", [curr_line | result])
    else
      do_wrap(rest, [], new_line, result)
    end
  end

  defp estimate_width(line) do
    String.length(line) * @avg_char_width  # e.g. 6 or 5.5
  end

  defp count_leading_spaces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end


  defp generate_page_content(lines) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {%{text: line, indent: indent}, index} ->
      y_pos = @start_y - (index * @line_height)
      x_offset = @left_margin + indent * 4  # 4pt per space (adjust as needed)
      "BT /F1 12 Tf 1 0 0 1 #{x_offset} #{y_pos} Tm (#{escape_text(line)}) Tj ET"
    end)
    |> Enum.join("\n")
  end

  defp escape_text(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("\r", "")
  end

  defp build_objects(objects) do
    # Start with offset for PDF header
    initial_offset = byte_size("%PDF-1.4\n")

    {body, xrefs, _final_offset} =
      Enum.reduce(objects, {"", [], initial_offset}, fn obj, {body_acc, xref_acc, current_offset} ->
        content = obj.content

        # Add xref entry for this object
        xref_entry = String.pad_leading("#{current_offset}", 10, "0") <> " 00000 n \n"

        # Update accumulator
        new_body = body_acc <> content
        new_xrefs = xref_acc ++ [xref_entry]
        new_offset = current_offset + byte_size(content)

        {new_body, new_xrefs, new_offset}
      end)

    {body, xrefs}
  end
end
