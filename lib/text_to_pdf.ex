defmodule TextToPdf do
  @moduledoc """
  A text-to-PDF generator for Elixir with proper Unicode and emoji support.
  Uses Identity-H encoding instead of WinAnsiEncoding for Unicode characters.
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

  # Font definitions - using TrueType fonts for Unicode support
  @fonts %{
    regular: %{name: "F1", base: "Helvetica", encoding: "WinAnsiEncoding"},
    bold: %{name: "F2", base: "Helvetica-Bold", encoding: "WinAnsiEncoding"},
    italic: %{name: "F3", base: "Helvetica-Oblique", encoding: "WinAnsiEncoding"},
    bold_italic: %{name: "F4", base: "Helvetica-BoldOblique", encoding: "WinAnsiEncoding"},
    unicode: %{name: "F5", base: "Arial-Unicode-MS", encoding: "Identity-H"}
  }

  # Regular fonts with WinAnsiEncoding (for basic Latin text)
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

  # Unicode font with Identity-H encoding for emojis and special characters
  @font_unicode """
  8 0 obj
  << /Type /Font
     /Subtype /Type0
     /Name /F5
     /BaseFont /Arial-Unicode-MS
     /Encoding /Identity-H
     /DescendantFonts [9 0 R]
     /ToUnicode 11 0 R
  >>
  endobj

  9 0 obj
  << /Type /Font
     /Subtype /CIDFontType2
     /BaseFont /Arial-Unicode-MS
     /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
     /FontDescriptor 10 0 R
     /DW 1000
  >>
  endobj

  10 0 obj
  << /Type /FontDescriptor
     /FontName /Arial-Unicode-MS
     /Flags 32
     /FontBBox [-1011 -329 2260 1078]
     /ItalicAngle 0
     /Ascent 1069
     /Descent -271
     /CapHeight 1069
     /StemV 0
  >>
  endobj

  11 0 obj
  << /Length 368 >>
  stream
  /CIDInit /ProcSet findresource begin
  12 dict begin
  begincmap
  /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def
  /CMapName /Adobe-Identity-UCS def
  /CMapType 2 def
  1 begincodespacerange
  <0000> <FFFF>
  endcodespacerange
  1 beginbfrange
  <0000> <FFFF> <0000>
  endbfrange
  endcmap
  CMapName currentdict /CMap defineresource pop
  end
  end
  endstream
  endobj
  """

  def generate_pdf(text, filename \\ "output.pdf") do
    File.mkdir_p!(Path.dirname(filename))

    # Parse text with formatting markup and detect Unicode characters
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
        id = 15 + page_index

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

    # Generate page objects with all font references
    {page_objs, page_ids} =
      content_ids
      |> Enum.with_index()
      |> Enum.map(fn {content_id, page_index} ->
        page_id = 25 + page_index

        page_obj = %{
          id: page_id,
          content: """
          #{page_id} 0 obj
          << /Type /Page
             /Parent 4 0 R
             /MediaBox [0 0 #{@page_width} #{@page_height}]
             /Contents #{content_id} 0 R
             /Resources << /Font << /F1 2 0 R /F2 3 0 R /F3 6 0 R /F4 7 0 R /F5 8 0 R >> >>
          >>
          endobj
          """
        }

        {page_obj, page_id}
      end)
      |> Enum.unzip()

    # Static PDF catalog and page tree
    catalog_objs = [
      %{id: 1, content: "1 0 obj\n<< >>\nendobj\n"},
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
      %{id: 7, content: @font_bold_italic},
      %{id: 8, content: @font_unicode}
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

  # Enhanced text parsing that detects Unicode characters
  defp parse_formatted_text(text) do
    text
    |> String.split("\n")
    |> Enum.map(&parse_line_formatting/1)
  end

  defp parse_line_formatting(""), do: %{segments: [%{text: "", style: :regular, underline: false}], indent: 0}

  defp parse_line_formatting(line) do
    indent = count_leading_spaces(line)
    trimmed_line = String.trim_leading(line)

    segments = parse_segments_with_unicode(trimmed_line)

    %{segments: segments, indent: indent}
  end

  # Parse segments and detect Unicode characters
  defp parse_segments_with_unicode(text) do
    # First split by Unicode characters (including emojis)
    parts = split_by_unicode(text)

    Enum.flat_map(parts, fn part ->
      if contains_unicode?(part) do
        [%{text: part, style: :unicode, underline: false}]
      else
        parse_segments(part)
      end
    end)
  end

  # Split text into ASCII and Unicode parts
  defp split_by_unicode(text) do
    # Regex to match Unicode characters outside basic ASCII range
    unicode_regex = ~r/[\x{80}-\x{10FFFF}]+/u

    Regex.split(unicode_regex, text, include_captures: true, trim: true)
    |> Enum.filter(&(&1 != ""))
  end

  # Check if text contains Unicode characters
  defp contains_unicode?(text) do
    # Check for characters outside basic ASCII range (0-127)
    text
    |> String.to_charlist()
    |> Enum.any?(&(&1 > 127))
  end

  # Parse segments with formatting markup
  defp parse_segments(text) do
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

  # Rest of the functions remain similar...
  defp wrap_formatted_line(%{segments: segments, indent: indent}) do
    combined_text = Enum.map_join(segments, "", & &1.text)

    if estimate_width(combined_text) <= @max_line_width do
      [%{segments: segments, indent: indent}]
    else
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

  # Enhanced segment content generation with proper Unicode handling
  defp generate_segment_content(%{text: text, style: style} = segment, x_pos, y_pos) do
    font_name = case style do
      :unicode -> @fonts[:unicode].name
      _ -> @fonts[style].name
    end

    # Handle Unicode text differently
    escaped_text = if style == :unicode do
      # For Unicode font, convert to hex representation
      text
      |> String.to_charlist()
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.map(&String.pad_leading(&1, 4, "0"))
      |> Enum.join("")
      |> then(&("<" <> &1 <> ">"))
    else
      # For regular fonts, use standard escaping
      escape_text(text)
      |> then(&("(" <> &1 <> ")"))
    end

    basic_content = "BT /#{font_name} 12 Tf 1 0 0 1 #{x_pos} #{y_pos} Tm #{escaped_text} Tj ET"

    underline = Map.get(segment, :underline, false)

    if underline and text != "" do
      text_width = estimate_width(text)
      underline_y = y_pos - 2
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
    initial_offset = byte_size("%PDF-1.4\n")

    {body, xrefs, _final_offset} =
      Enum.reduce(objects, {"", [], initial_offset}, fn obj, {body_acc, xref_acc, current_offset} ->
        content = obj.content
        xref_entry = String.pad_leading("#{current_offset}", 10, "0") <> " 00000 n \n"
        new_body = body_acc <> content
        new_xrefs = xref_acc ++ [xref_entry]
        new_offset = current_offset + byte_size(content)

        {new_body, new_xrefs, new_offset}
      end)

    {body, xrefs}
  end
end
