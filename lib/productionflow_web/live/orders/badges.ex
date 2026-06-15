defmodule ProductionflowWeb.Orders.Badges do
  @moduledoc "Shared label + badge-colour helpers for order/line/step statuses."

  @doc "Human label for any status atom, e.g. :in_production → \"In production\"."
  def status_label(status), do: Phoenix.Naming.humanize(status)

  @doc "daisyUI badge class for an order status."
  def order_status_class(:draft), do: "badge-ghost"
  def order_status_class(:confirmed), do: "badge-info"
  def order_status_class(:in_production), do: "badge-warning"
  def order_status_class(:completed), do: "badge-success"
  def order_status_class(:cancelled), do: "badge-error"

  @doc "daisyUI badge class for a route-step / derived line status."
  def step_status_class(:blocked), do: "badge-error"
  def step_status_class(:pending), do: "badge-ghost"
  def step_status_class(:in_progress), do: "badge-warning"
  def step_status_class(:done), do: "badge-success"
end
