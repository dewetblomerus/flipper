defmodule Flipper.Drafts.Decision do
  @moduledoc """
  A choice a person owes a draft.
  """

  import Ecto.Query

  alias Flipper.Drafts.Draft
  alias Flipper.Repo

  defstruct [:draft_id, :kind]

  # Furthest along first.
  @kinds [field_removals: "field_removals_drafted", photo_pick: "photo_edits_drafted"]

  @doc """
  Lists pending decisions: furthest along first, then oldest draft.
  """
  def pending do
    for {kind, state} <- @kinds, id <- draft_ids(state) do
      %__MODULE__{draft_id: id, kind: kind}
    end
  end

  defp draft_ids(state) do
    Repo.all(from d in Draft, where: d.state == ^state, order_by: d.id, select: d.id)
  end
end
