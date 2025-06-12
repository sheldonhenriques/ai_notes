defmodule AiNotesWeb.PdfController do
  use AiNotesWeb, :controller
  alias AiNotes.Notes
  alias TextToPdf

  def note_pdf(conn, %{"id" => id}) do
    note = Notes.get_note!(id)
    filename = "note_#{id}.pdf"
    {:ok, pdf_path} = TextToPdf.generate_pdf("#{note.title}: #{note.content}", "priv/static/tmp/#{filename}")

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_file(200, pdf_path)
  end
end
