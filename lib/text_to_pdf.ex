defmodule TextToPdf do
  @moduledoc """
  A text-to-PDF generator for Elixir with support for text formatting.
  Supports multi-line, multi-page PDFs with bold, italic, bold+italic, and underline.
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
  @avg_char_width 5.5
  @chars_per_line div(@max_line_width, @avg_char_width |> round)
  @lines_per_page div(@start_y - @bottom_margin, @line_height)

  # Font definitions for different styles
  @fonts %{
    regular: %{name: "F1", base: "Helvetica"},
    bold: %{name: "F2", base: "Helvetica-Bold"},
    italic: %{name: "F3", base: "Helvetica-Oblique"},
    bold_italic: %{name: "F4", base: "Helvetica-BoldOblique"}
  }

  @font_regular """
  2 0 obj
  << /Type /Font
     /Subtype /Type1
     /Name /F1
     /BaseFont /Helvetica
     /Encoding /WinAnsiEncoding
  >>
  endobj
  """

  @font_bold """
  3 0 obj
  << /Type /Font
     /Subtype /Type1
     /Name /F2
     /BaseFont /Helvetica-Bold
     /Encoding /WinAnsiEncoding
  >>
  endobj
  """

  @font_italic """
  6 0 obj
  << /Type /Font
     /Subtype /Type1
     /Name /F3
     /BaseFont /Helvetica-Oblique
     /Encoding /WinAnsiEncoding
  >>
  endobj
  """

  @font_bold_italic """
  7 0 obj
  << /Type /Font
     /Subtype /Type1
     /Name /F4
     /BaseFont /Helvetica-BoldOblique
     /Encoding /WinAnsiEncoding
  >>
  endobj
  """

  def generate_pdf(text, filename \\ "output.pdf") do
    File.mkdir_p!(Path.dirname(filename))

    # Parse text with formatting markup
    parsed_lines = parse_formatted_text(text)

    # Process lines with word wrapping while preserving formatting
    lines = Enum.flat_map(parsed_lines, &wrap_formatted_line/1)

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
             /Resources << /Font << /F1 2 0 R /F2 3 0 R /F3 6 0 R /F4 7 0 R >> >>
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
      %{id: 2, content: @font_regular},
      %{id: 3, content: @font_bold},
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
      """},
      %{id: 6, content: @font_italic},
      %{id: 7, content: @font_bold_italic}
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

  # Parse text with markdown-style formatting
  defp parse_formatted_text(text) do
    text
    |> String.split("\n")
    |> Enum.map(&parse_line_formatting/1)
  end

  defp parse_line_formatting(""), do: %{segments: [%{text: "", style: :regular, underline: false}], indent: 0}

  defp parse_line_formatting(line) do
    indent = count_leading_spaces(line)
    trimmed_line = String.trim_leading(line)

    segments = parse_segments(trimmed_line)

    %{segments: segments, indent: indent}
  end

  # Parse segments with formatting markup
  defp parse_segments(text) do
    # Match patterns: <u>text</u>, <b>text</b>, <i>text</i>, ***text***, **text**, *text*, __text__, _text_
    regex = ~r/(<u>.*?<\/u>|<b>.*?<\/b>|<i>.*?<\/i>|\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|__.*?__|_.*?_|[^*_<]+)/

    Regex.scan(regex, text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&classify_segment/1)
  end

  defp classify_segment(segment) do
    cond do
      String.starts_with?(segment, "<u>") and String.ends_with?(segment, "</u>") ->
        %{text: String.slice(segment, 3..-5), style: :regular, underline: true}

      String.starts_with?(segment, "<b>") and String.ends_with?(segment, "</b>") ->
        %{text: String.slice(segment, 3..-5), style: :bold, underline: false}

      String.starts_with?(segment, "<i>") and String.ends_with?(segment, "</i>") ->
        %{text: String.slice(segment, 3..-5), style: :italic, underline: false}

      String.starts_with?(segment, "***") and String.ends_with?(segment, "***") ->
        %{text: String.slice(segment, 3..-4), style: :bold_italic, underline: false}

      String.starts_with?(segment, "**") and String.ends_with?(segment, "**") ->
        %{text: String.slice(segment, 2..-3), style: :bold, underline: false}

      String.starts_with?(segment, "*") and String.ends_with?(segment, "*") ->
        %{text: String.slice(segment, 1..-2), style: :italic, underline: false}

      String.starts_with?(segment, "__") and String.ends_with?(segment, "__") ->
        %{text: String.slice(segment, 2..-3), style: :regular, underline: true}

      String.starts_with?(segment, "_") and String.ends_with?(segment, "_") ->
        %{text: String.slice(segment, 1..-2), style: :italic, underline: false}

      true ->
        %{text: segment, style: :regular, underline: false}
    end
  end

  defp wrap_formatted_line(%{segments: segments, indent: indent}) do
    # For now, treat each formatted line as a single unit
    # More sophisticated wrapping would need to handle segments separately
    combined_text = Enum.map_join(segments, "", & &1.text)

    if estimate_width(combined_text) <= @max_line_width do
      [%{segments: segments, indent: indent}]
    else
      # Simple fallback: split into words and wrap
      words = String.split(combined_text)
      wrapped_lines = do_wrap_words(words, [], "", [])

      Enum.map(wrapped_lines, fn line_text ->
        %{segments: [%{text: line_text, style: :regular, underline: false}], indent: indent}
      end)
    end
  end

  defp do_wrap_words([], _acc, curr_line, result) when curr_line != "" do
    Enum.reverse([curr_line | result])
  end

  defp do_wrap_words([], _acc, "", result) do
    Enum.reverse(result)
  end

  defp do_wrap_words([word | rest], _acc, curr_line, result) do
    new_line = if curr_line == "", do: word, else: curr_line <> " " <> word
    est_width = estimate_width(new_line)

    if est_width > @max_line_width and curr_line != "" do
      do_wrap_words([word | rest], [], "", [curr_line | result])
    else
      do_wrap_words(rest, [], new_line, result)
    end
  end

  defp estimate_width(line) do
    String.length(line) * @avg_char_width
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
    |> Enum.map(fn {line_data, index} ->
      generate_line_content(line_data, index)
    end)
    |> Enum.join("\n")
  end

  defp generate_line_content(%{segments: segments, indent: indent}, line_index) do
    y_pos = @start_y - (line_index * @line_height)
    base_x = @left_margin + indent * 4

    {content, _final_x} =
      Enum.reduce(segments, {"", base_x}, fn segment, {acc_content, current_x} ->
        segment_content = generate_segment_content(segment, current_x, y_pos)
        text_width = estimate_width(segment.text)

        {acc_content <> segment_content, current_x + text_width}
      end)

    content
  end

  # Fixed function: Use absolute positioning (Tm) instead of relative positioning (Td)
  defp generate_segment_content(%{text: text, style: style} = segment, x_pos, y_pos) do
    font_name = @fonts[style].name
    escaped_text = escape_text(text)

    # Use Tm (text matrix) for absolute positioning instead of Td (relative positioning)
    basic_content = "BT /#{font_name} 12 Tf 1 0 0 1 #{x_pos} #{y_pos} Tm (#{escaped_text}) Tj ET"

    underline = Map.get(segment, :underline, false)

    if underline and text != "" do
      text_width = estimate_width(text)
      underline_y = y_pos - 2
      # Set line width and draw underline
      underline_content = "q\n1 w\n#{x_pos} #{underline_y} m\n#{x_pos + text_width} #{underline_y} l\nS\nQ"
      basic_content <> "\n" <> underline_content
    else
      basic_content
    end
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
