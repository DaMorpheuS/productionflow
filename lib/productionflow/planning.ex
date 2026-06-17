defmodule Productionflow.Planning do
  @moduledoc """
  The Planning context: a production scheduling board that places order route
  steps onto machines over time.

  Each machine owns a queue of scheduled steps (`Planning.ScheduledStep`),
  ordered by `position` and packed back-to-back across the machine's working
  hours (`Production.Machine` working_day_start/end + working_days). Durations
  come from the snapshot already on each `Orders.OrderRouteStep`; the scheduler
  derives concrete `starts_at`/`ends_at` and recomputes a machine's whole queue
  whenever its membership or order changes.
  """

  import Ecto.Query, warn: false
  alias Productionflow.Repo
  alias Productionflow.Planning.Settings

  ## Settings (singleton)

  @doc "Returns the planning settings, creating the singleton row if missing."
  def get_settings do
    Repo.get(Settings, 1) || create_default_settings()
  end

  defp create_default_settings do
    %Settings{id: 1}
    |> Settings.changeset(%{})
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)

    Repo.get!(Settings, 1)
  end

  @doc "Returns a changeset for the settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc "Updates the planning settings."
  def update_settings(attrs) do
    get_settings()
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  The date the scheduler packs queues forward from: the configured
  `schedule_from`, never earlier than today.
  """
  def schedule_anchor_date do
    today = Date.utc_today()

    case get_settings().schedule_from do
      nil -> today
      date -> if Date.compare(date, today) == :lt, do: today, else: date
    end
  end
end
