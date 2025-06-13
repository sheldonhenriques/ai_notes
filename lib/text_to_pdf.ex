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
  @table_cell_padding 8
  @table_row_height 24
  @header_row_height 28
  @line_width 0.5
  @header_bg_gray 0.95
  @alt_row_bg_gray 0.98
  @border_gray 0.8

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
    parsed_content = parse_formatted_text(text)

    # Process content blocks (text and tables)
    processed_content = Enum.flat_map(parsed_content, &process_content_block/1)

    pages = chunk_content_into_pages(processed_content)

    # Generate PDF stream objects for each page's content
    {content_objs, content_ids} =
      pages
      |> Enum.with_index()
      |> Enum.map(fn {page_content, page_index} ->
        content_stream = generate_page_content(page_content)
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
    |> group_table_blocks()
  end

  defp parse_line_formatting(""), do: %{type: :text, segments: [%{text: "", style: :regular, underline: false}], indent: 0}

  defp parse_line_formatting(line) do
    indent = count_leading_spaces(line)
    trimmed_line = String.trim_leading(line)

    segments = parse_segments_with_unicode(trimmed_line)

    %{type: :text, segments: segments, indent: indent}
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

  # Process content blocks (text lines or tables)
  defp process_content_block({:text, line}) do
    formatted_line = parse_line_formatting(line)
    # Apply word wrapping to text lines
    wrap_formatted_line(formatted_line)
  end

  defp process_content_block({:table, table_data}) do
    [%{type: :table, data: table_data}]
  end

  # Rest of the functions remain similar...
  defp wrap_formatted_line(%{type: :text, segments: segments, indent: indent} = line) do
    # Check if this is a table line (contains table border characters)
    combined_text = Enum.map_join(segments, "", & &1.text)

    if String.contains?(combined_text, ["+", "|"]) and
      (String.contains?(combined_text, "-") or String.length(combined_text) > @chars_per_line * 0.8) do
      # This is likely a table line, don't wrap it
      [line]
    else
      # Regular text wrapping logic
      if estimate_width(combined_text) <= @max_line_width do
        [line]
      else
        words = String.split(combined_text)
        wrapped_lines = do_wrap_words(words, [], "", [])

        Enum.map(wrapped_lines, fn line_text ->
          %{type: :text, segments: [%{text: line_text, style: :regular, underline: false}], indent: indent}
        end)
      end
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

  # Improved content chunking that handles tables properly
  defp chunk_content_into_pages(content) do
    content
    |> Enum.reduce({[], [], 0}, fn item, {pages, current_page, current_lines} ->
      lines_needed = case item.type do
        :text -> 1
        :table -> length(item.data.rows) + 2  # Add space for table borders
      end

      if current_lines + lines_needed > @lines_per_page and current_page != [] do
        # Start new page
        {pages ++ [current_page], [item], lines_needed}
      else
        # Add to current page
        {pages, current_page ++ [item], current_lines + lines_needed}
      end
    end)
    |> then(fn {pages, current_page, _} ->
      if current_page != [], do: pages ++ [current_page], else: pages
    end)
  end

  defp generate_page_content(content_items) do
    {_final_content, _final_y} =
      Enum.reduce(content_items, {"", @start_y}, fn item, {acc_content, current_y} ->
        case item.type do
          :text ->
            line_content = generate_text_line_content(item, current_y)
            {acc_content <> line_content <> "\n", current_y - @line_height}

          :table ->
            table_content = generate_table_content_pdf(item.data, current_y)
            table_height = (length(item.data.rows) * @table_row_height) + @header_row_height
            {acc_content <> table_content <> "\n", current_y - table_height - 10}
        end
      end)

    _final_content
  end

  defp generate_text_line_content(%{segments: segments, indent: indent}, y_pos) do
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

  # Improved table content generation for PDF graphics
  defp generate_table_content_pdf(table_data, start_y) do
    rows = table_data.rows
    col_widths = table_data.col_widths

    # Center the table horizontally
    total_table_width = Enum.sum(col_widths)
    start_x = @left_margin + (@max_line_width - total_table_width) / 2

    # Generate table structure (borders and backgrounds)
    table_structure = draw_table_structure(rows, col_widths, start_x, start_y)

    # Generate table text content
    table_text = draw_table_text(rows, col_widths, start_x, start_y)

    table_structure <> "\n" <> table_text
  end

  defp draw_table_structure(rows, col_widths, start_x, start_y) do
    num_rows = length(rows)
    total_width = Enum.sum(col_widths)
    total_height = @header_row_height + (num_rows - 1) * @table_row_height

    structure = []

    # Header background
    structure = structure ++ [
      "q",  # Save graphics state
      "#{@header_bg_gray} g",  # Set fill color (light gray)
      "#{start_x} #{start_y - @header_row_height} #{total_width} #{@header_row_height} re",  # Rectangle
      "f",  # Fill
      "Q"   # Restore graphics state
    ]

    # Alternating row backgrounds
    structure = structure ++ draw_alternating_backgrounds(rows, col_widths, start_x, start_y)

    # Horizontal lines
    structure = structure ++ draw_horizontal_lines(num_rows, total_width, start_x, start_y)

    # Vertical lines
    structure = structure ++ draw_vertical_lines(col_widths, total_height, start_x, start_y)

    Enum.join(structure, "\n")
  end

  defp draw_alternating_backgrounds(rows, col_widths, start_x, start_y) do
    total_width = Enum.sum(col_widths)

    rows
    |> Enum.drop(1)  # Skip header row
    |> Enum.with_index(1)
    |> Enum.filter(fn {_row, index} -> rem(index, 2) == 0 end)  # Even rows only
    |> Enum.flat_map(fn {_row, index} ->
      y_pos = start_y - @header_row_height - (index * @table_row_height)
      [
        "q",
        "#{@alt_row_bg_gray} g",
        "#{start_x} #{y_pos} #{total_width} #{@table_row_height} re",
        "f",
        "Q"
      ]
    end)
  end

  defp draw_horizontal_lines(num_rows, total_width, start_x, start_y) do
    # Top border
    lines = [
      "q",
      "#{@line_width} w",
      "#{@border_gray} G",
      "#{start_x} #{start_y} m",
      "#{start_x + total_width} #{start_y} l",
      "S"
    ]

    # Header separator (thicker line)
    lines = lines ++ [
      "1 w",  # Thicker line for header
      "0.6 G",  # Darker gray
      "#{start_x} #{start_y - @header_row_height} m",
      "#{start_x + total_width} #{start_y - @header_row_height} l",
      "S"
    ]

    # Row separators (thin lines)
    lines = lines ++
      Enum.flat_map(1..(num_rows-1), fn row_index ->
        y_pos = start_y - @header_row_height - (row_index * @table_row_height)
        [
          "#{@line_width} w",
          "#{@border_gray} G",
          "#{start_x} #{y_pos} m",
          "#{start_x + total_width} #{y_pos} l",
          "S"
        ]
      end)

    # Bottom border
    bottom_y = start_y - @header_row_height - ((num_rows - 1) * @table_row_height)
    lines = lines ++ [
      "#{@line_width} w",
      "#{@border_gray} G",
      "#{start_x} #{bottom_y} m",
      "#{start_x + total_width} #{bottom_y} l",
      "S",
      "Q"
    ]

    lines
  end

  defp draw_vertical_lines(col_widths, total_height, start_x, start_y) do
    lines = [
      "q",
      "#{@line_width} w",
      "#{@border_gray} G"
    ]

    # Left border
    lines = lines ++ [
      "#{start_x} #{start_y} m",
      "#{start_x} #{start_y - total_height} l",
      "S"
    ]

    # Column separators and right border
    {lines, _final_x} =
      Enum.reduce(col_widths, {lines, start_x}, fn width, {acc_lines, current_x} ->
        new_x = current_x + width
        new_lines = acc_lines ++ [
          "#{new_x} #{start_y} m",
          "#{new_x} #{start_y - total_height} l",
          "S"
        ]
        {new_lines, new_x}
      end)

    lines ++ ["Q"]
  end


  defp draw_table_text(rows, col_widths, start_x, start_y) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, row_index} ->
      draw_row_text_centered(row, col_widths, start_x, start_y, row_index)
    end)
    |> Enum.join("\n")
  end

  defp draw_row_text_centered(row, col_widths, start_x, start_y, row_index) do
    row_height = if row_index == 0, do: @header_row_height, else: @table_row_height
     y_pos = start_y - (row_height * 0.3) - (row_index * @table_row_height) -
          (if row_index > 0, do: @header_row_height - @table_row_height, else: 0)

    font = if row_index == 0, do: "F2", else: "F1"  # Bold for headers
    font_size = 10

    row
    |> Enum.with_index()
    |> Enum.map(fn {cell, col_index} ->
      col_widths_before = Enum.take(col_widths, col_index) |> Enum.sum()
      col_width = Enum.at(col_widths, col_index)

      # More accurate text width calculation for centering
      # Estimate character width based on font size (average for Helvetica)
      char_width = font_size * 0.55  # More accurate character width
      text_width = String.length(cell) * char_width

      # Calculate cell boundaries
      cell_left = start_x + col_widths_before
      cell_right = cell_left + col_width
      cell_center = cell_left + (col_width / 2)

      # Center the text
      text_start_x = cell_center - (text_width / 2)

      # Ensure text doesn't go outside cell boundaries (with padding)
      min_x = cell_left + @table_cell_padding
      max_x = cell_right - @table_cell_padding - text_width
      final_x = max(min_x, min(text_start_x, max_x))

      escaped_text = escape_text(cell)
      "BT /#{font} #{font_size} Tf 1 0 0 1 #{final_x} #{y_pos} Tm (#{escaped_text}) Tj ET"
    end)
    |> Enum.join("\n")
  end

  # Group consecutive table rows together
  defp group_table_blocks(lines) do
    lines
    |> Enum.reduce({[], []}, fn line, {blocks, current_table} ->
      cond do
        String.contains?(line, "|") and String.trim(line) != "" ->
          # This is a table row
          {blocks, current_table ++ [line]}

        current_table != [] ->
          # End of table block
          table_block = {:table, parse_table(current_table)}
          {blocks ++ [table_block, {:text, line}], []}

        true ->
          # Regular text line
          {blocks ++ [{:text, line}], []}
      end
    end)
    |> then(fn {blocks, remaining_table} ->
      if remaining_table != [] do
        blocks ++ [table: parse_table(remaining_table)]
      else
        blocks
      end
    end)
  end

  # Parse table into structured data
  defp parse_table(table_lines) do
    # Filter out separator lines (lines with only |, -, and spaces)
    data_lines = Enum.filter(table_lines, fn line ->
      cleaned = String.replace(line, ~r/[\|\-\s]/, "")
      cleaned != ""
    end)

    # Parse each row
    rows = Enum.map(data_lines, &parse_table_row/1)

    # Calculate column widths
    max_cols = Enum.max(Enum.map(rows, &length/1), fn -> 0 end)
    col_widths = calculate_column_widths(rows, max_cols)

    %{rows: rows, col_widths: col_widths}
  end

  defp parse_table_row(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  defp calculate_column_widths(rows, max_cols) do
    # Calculate based on content length with available page width
    base_widths = 0..(max_cols - 1)
    |> Enum.map(fn col_index ->
      max_content_length =
        rows
        |> Enum.map(fn row ->
          Enum.at(row, col_index, "")
          |> String.length()
        end)
        |> Enum.max(fn -> 0 end)

      # Minimum width of 60, scale with content
      max(max_content_length * 6 + @table_cell_padding * 2, 60)
    end)

    # Scale to fit page width
    total_width = Enum.sum(base_widths)
    available_width = @max_line_width - 20  # Leave some margin

    if total_width > available_width do
      scale_factor = available_width / total_width
      Enum.map(base_widths, &round(&1 * scale_factor))
    else
      base_widths
    end
  end
end
