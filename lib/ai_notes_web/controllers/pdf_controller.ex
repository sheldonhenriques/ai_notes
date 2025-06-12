defmodule AiNotesWeb.PdfController do
  use AiNotesWeb, :controller
  alias AiNotes.Notes
  alias TextToPdf
  require Logger

  def note_pdf(conn, %{"id" => id}) do
    note = Notes.get_note!(id)

    # Debug: Let's see what we're actually getting from the database
    Logger.info("Raw note content: #{inspect(note.content)}")
    Logger.info("Content length: #{String.length(note.content)}")
    Logger.info("Contains newlines: #{String.contains?(note.content, "\n")}")
    Logger.info("Contains \\n: #{String.contains?(note.content, "\\n")}")

    # Process the content to handle escaped newlines if they exist
    processed_content = process_content(note.content)
    Logger.info("Processed content: #{inspect(processed_content)}")

    full_text = "#{note.title}\n\n#{processed_content}"

    filename = "note_#{id}.pdf"
    {:ok, pdf_path} = TextToPdf.generate_pdf(full_text, "priv/static/tmp/#{filename}")

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_file(200, pdf_path)
  end

  # Helper function to process content and handle different newline formats
  defp process_content(content) when is_binary(content) do
    content
    |> String.replace("\\n", "\n")  # Convert escaped newlines to actual newlines
    |> String.replace("\\r\\n", "\n")  # Handle Windows line endings
    |> String.replace("\\r", "\n")     # Handle old Mac line endings
    |> String.replace("\r\n", "\n")    # Normalize Windows line endings
    |> String.replace("\r", "\n")      # Normalize Mac line endings
  end

  defp process_content(content), do: to_string(content)
end
