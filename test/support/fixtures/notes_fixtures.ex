defmodule AiNotes.NotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AiNotes.Notes` context.
  """

  @doc """
  Generate a note.
  """
  def note_fixture(attrs \\ %{}) do
    {:ok, note} =
      attrs
      |> Enum.into(%{
        content: "some content",
        title: "some title"
      })
      |> AiNotes.Notes.create_note()

    note
  end
end
