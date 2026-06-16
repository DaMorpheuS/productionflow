defmodule ProductionflowWeb.QuoteLive do
  @moduledoc "Public, no-login page where a customer reviews and accepts/declines a quote."
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.Orders
  alias Productionflow.Orders.Order

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    order = Orders.get_quote_by_token(token)

    {:ok,
     socket
     |> assign(:page_title, gettext("Quote"))
     |> assign(:order, order)
     |> assign(:declining, false)
     |> assign(:totals, order && Orders.order_totals(order))}
  end

  @impl true
  def render(%{order: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md py-10 text-center">
        <.header>
          {gettext("Quote unavailable")}
          <:subtitle>{gettext("This link is invalid or has expired.")}</:subtitle>
        </.header>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-6 py-6">
        <.header>
          {gettext("Quote %{n}", n: @order.quote_number)}
          <span class={["badge ml-2", order_status_class(@order.status)]}>
            {status_label(@order.status)}
          </span>
          <:subtitle>{@order.relation.name}</:subtitle>
        </.header>

        <section class="rounded-xl border border-base-300 bg-base-100 p-6">
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Item")}</th>
                <th>{gettext("Qty")}</th>
                <th>{gettext("Unit price")}</th>
                <th>{gettext("Total")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={line <- @order.lines}>
                <td>{line.description}</td>
                <td>{qty(line.quantity)} {line.output_unit}</td>
                <td>{money(line.unit_price)}</td>
                <td>{money(line.total_price)}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="font-semibold">
                <td colspan="3">{gettext("Total")}</td>
                <td>{money(@totals.price)}</td>
              </tr>
            </tfoot>
          </table>
          <p :if={@order.valid_until} class="mt-2 text-sm text-base-content/60">
            {gettext("Valid until %{date}", date: @order.valid_until)}
          </p>
        </section>

        <div :if={@order.status == :sent} class="flex flex-wrap items-start gap-3">
          <.button variant="primary" phx-click="accept" data-confirm={gettext("Accept this quote?")}>
            {gettext("Accept quote")}
          </.button>
          <.button :if={not @declining} phx-click="show_decline">{gettext("Decline")}</.button>

          <.form
            :if={@declining}
            for={%{}}
            id="public-decline-form"
            phx-submit="decline"
            class="flex flex-wrap items-end gap-2"
          >
            <.input
              name="decline_reason"
              value=""
              type="select"
              label={gettext("Reason")}
              prompt={gettext("Choose a reason")}
              options={decline_reason_options()}
            />
            <.input name="decline_notes" value="" type="text" label={gettext("Notes")} />
            <.button variant="primary">{gettext("Submit decline")}</.button>
          </.form>
        </div>

        <div :if={@order.status == :accepted} class="alert alert-success">
          {gettext("Thank you — your quote has been accepted.")}
        </div>
        <div :if={@order.status == :declined} class="alert alert-info">
          {gettext("You have declined this quote. We'll be in touch.")}
        </div>
        <div :if={@order.status not in [:sent, :accepted, :declined]} class="alert">
          {gettext("This quote is no longer open for a decision.")}
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("show_decline", _params, socket) do
    {:noreply, assign(socket, :declining, true)}
  end

  def handle_event("accept", _params, socket) do
    case Orders.accept_quote(socket.assigns.order) do
      {:ok, _} ->
        {:noreply, decided(socket, gettext("Quote accepted. Thank you!"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("This quote can no longer be accepted."))}
    end
  end

  def handle_event("decline", params, socket) do
    case Orders.decline_quote(socket.assigns.order, params) do
      {:ok, _} -> {:noreply, decided(socket, gettext("Quote declined."))}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Please choose a reason."))}
    end
  end

  # After a decision, consume the link's tokens and refresh from the document.
  defp decided(socket, message) do
    order = socket.assigns.order
    Orders.consume_quote_tokens(order)
    refreshed = Orders.get_order!(order.id)

    socket
    |> put_flash(:info, message)
    |> assign(:order, refreshed)
    |> assign(:declining, false)
    |> assign(:totals, Orders.order_totals(refreshed))
  end

  defp decline_reason_options do
    Enum.map(Order.decline_reasons(), &{status_label(&1), to_string(&1)})
  end

  defp qty(%Decimal{} = d), do: Decimal.to_string(Decimal.normalize(d), :normal)
  defp qty(_), do: ""
end
