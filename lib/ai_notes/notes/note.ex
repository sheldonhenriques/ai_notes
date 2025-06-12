defmodule AiNotes.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :title, :string
    field :content, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, max: 255)
    |> validate_length(:content, max: 10_000)
  end
end
