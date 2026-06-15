defmodule ProductionflowWeb.Pricing.QuoteLive do
  use ProductionflowWeb, :live_view

  alias Productionflow.{Pricing, Catalog, CRM}
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Quote"))
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "pricing.manage"))
     |> assign(:template_options, template_options())
     |> assign(:customer_options, customer_options())
     |> assign(:template_id, params["template_id"] || "")
     |> assign(:quantity, "100")
     |> assign(:relation_id, "")
     |> recompute()}
  end

  @impl true
  def handle_event("recompute", params, socket) do
    {:noreply,
     socket
     |> assign(:template_id, params["template_id"] || "")
     |> assign(:quantity, params["quantity"] || "")
     |> assign(:relation_id, params["relation_id"] || "")
     |> recompute()}
  end

  defp recompute(socket) do
    quote =
      build_quote(socket.assigns.template_id, socket.assigns.quantity, socket.assigns.relation_id)

    assign(socket, :quote, quote)
  end

  defp build_quote(template_id, quantity, relation_id) do
    with {:ok, template} <- fetch_template(template_id),
         qty when not is_nil(qty) <- parse_quantity(quantity) do
      Pricing.quote(template, qty, relation: fetch_relation(relation_id))
    else
      _ -> nil
    end
  end

  defp fetch_template(""), do: :error
  defp fetch_template(id), do: {:ok, Catalog.get_product_template!(id)}

  defp fetch_relation(""), do: nil
  defp fetch_relation(id), do: CRM.get_relation!(id)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {gettext("Quote")}
        <:subtitle>{gettext("Cost build-up, default margin and price-list resolution.")}</:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/pricing/settings"}>
            {gettext("Default margin")}
          </.button>
        </:actions>
      </.header>

      <.form
        for={%{}}
        id="quote-form"
        phx-change="recompute"
        class="grid items-end gap-3 sm:grid-cols-3"
      >
        <.input
          name="template_id"
          value={@template_id}
          type="select"
          label={gettext("Product")}
          prompt={gettext("Choose a product")}
          options={@template_options}
        />
        <.input
          name="quantity"
          value={@quantity}
          type="number"
          step="1"
          min="0"
          label={gettext("Quantity")}
        />
        <.input
          name="relation_id"
          value={@relation_id}
          type="select"
          label={gettext("Customer")}
          prompt={gettext("No customer (general)")}
          options={@customer_options}
        />
      </.form>

      <div :if={@quote} class="mt-6 grid gap-6 lg:grid-cols-2">
        <section class="rounded-xl border border-base-300 bg-base-100 p-6">
          <h2 class="mb-3 text-base font-semibold">{gettext("Internal cost")}</h2>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
            <.detail label={gettext("Duration")} value={duration(@quote.estimate.duration_minutes)} />
            <.detail label={gettext("Machine")} value={money(@quote.estimate.machine_cost)} />
            <.detail label={gettext("Labour")} value={money(@quote.estimate.labour_cost)} />
            <.detail label={gettext("Energy")} value={money(@quote.estimate.energy_cost)} />
            <.detail label={gettext("Materials")} value={money(@quote.estimate.material_cost)} />
            <.detail label={gettext("Total cost")} value={money(@quote.internal_total_cost)} />
            <.detail label={gettext("Cost per unit")} value={money(@quote.internal_unit_cost)} />
          </dl>
        </section>

        <section class="rounded-xl border border-base-300 bg-base-100 p-6">
          <h2 class="mb-3 text-base font-semibold">{gettext("Price")}</h2>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
            <.detail
              label={gettext("Default margin")}
              value={Decimal.to_string(@quote.effective_margin_pct) <> "%"}
            />
            <.detail label={gettext("Default unit price")} value={money(@quote.default_unit_price)} />
            <.detail label={gettext("Source")} value={source_label(@quote.price_source)} />
            <.detail label={gettext("Unit price")} value={money(@quote.unit_price)} />
            <.detail label={gettext("Total price")} value={money(@quote.total_price)} />
            <.detail label={gettext("Unit margin")} value={margin_value(@quote.unit_margin)} />
            <.detail label={gettext("Total margin")} value={margin_value(@quote.total_margin)} />
            <.detail label={gettext("Margin of price")} value={pct(@quote.margin_pct_of_price)} />
          </dl>

          <div :if={@quote.below_cost?} class="mt-4 rounded-lg bg-error/10 p-3 text-sm text-error">
            <.icon name="hero-exclamation-triangle" class="size-4" />
            {gettext("This price is below internal cost.")}
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp detail(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  defp source_label(:price_list), do: gettext("Price list")
  defp source_label(:calculated), do: gettext("Calculated (margin)")

  defp margin_value(nil), do: "—"
  defp margin_value(%Decimal{} = amount), do: money(amount)

  defp pct(nil), do: "—"
  defp pct(%Decimal{} = value), do: Decimal.to_string(Decimal.round(value, 1)) <> "%"

  defp parse_quantity(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> if Decimal.compare(decimal, 0) == :gt, do: decimal, else: nil
      _ -> nil
    end
  end

  defp parse_quantity(_), do: nil

  defp template_options do
    Catalog.list_product_templates() |> Enum.map(&{&1.name, &1.id})
  end

  defp customer_options do
    CRM.list_relations(type: :customer) |> Enum.map(&{&1.name, &1.id})
  end
end
