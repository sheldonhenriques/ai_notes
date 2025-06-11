defmodule AiNotes.Repo do
  use Ecto.Repo,
    otp_app: :ai_notes,
    adapter: Ecto.Adapters.Postgres
end
