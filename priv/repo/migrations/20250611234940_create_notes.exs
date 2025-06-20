defmodule AiNotes.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :title, :string
      add :content, :text

      timestamps(type: :utc_datetime)
    end
  end
end

defmodule AiNotes.Repo.Migrations.ChangeNotesContentToText do
  use Ecto.Migration

  def change do
    alter table(:notes) do
      modify :content, :text
    end
  end
end
