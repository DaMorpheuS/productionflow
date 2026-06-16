defmodule ProductionflowWeb.Orders.OrderLive.Show do
  use ProductionflowWeb, :live_view

  import ProductionflowWeb.Orders.Badges

  alias Productionflow.{Orders, Catalog, CRM}
  alias Productionflow.Orders.Order
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "orders.manage"))
     |> assign(:template_options, template_options())
     |> assign(:add_line, %{"product_template_id" => "", "quantity" => "100"})
     |> load_order(id)}
  end

  defp load_order(socket, id) do
    order = Orders.get_order!(id)

    socket
    |> assign(:order, order)
    |> assign(:page_title, order.number || order.quote_number)
    |> assign(:can_edit, socket.assigns.can_manage and Order.editable?(order))
    |> assign(:pending_action, nil)
    |> assign(:totals, Orders.order_totals(order))
    |> assign(:all_done, Orders.all_steps_done?(order.id))
    |> assign(:address_options, address_options(order))
  end

  defp address_options(order) do
    CRM.get_relation!(order.relation_id).addresses
    |> Enum.map(&{format_address(&1), &1.id})
  end

  defp reload(socket, message) do
    socket |> put_flash(:info, message) |> load_order(socket.assigns.order.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@order.number || @order.quote_number}
        <span class={["badge ml-2", order_status_class(@order.status)]}>
          {status_label(@order.status)}
        </span>
        <span :if={@order.archived_at} class="badge badge-ghost ml-1">{gettext("Archived")}</span>
        <:subtitle>
          <.link navigate={back_path(@order)} class="hover:underline">
            &larr; {back_label(@order)}
          </.link>
          · {@order.relation.name}
        </:subtitle>
        <:actions>
          <.button :if={@can_edit} navigate={~p"/orders/#{@order}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button
            :if={@can_manage and :sent in Order.next_statuses(@order.status)}
            variant="primary"
            phx-click="send"
          >
            {gettext("Send to customer")}
          </.button>
          <.button
            :if={@can_manage and :accepted in Order.next_statuses(@order.status)}
            variant="primary"
            phx-click="accept"
            data-confirm={gettext("Accept this quote and turn it into an order?")}
          >
            {gettext("Accept")}
          </.button>
          <.button
            :if={@can_manage and :declined in Order.next_statuses(@order.status)}
            phx-click="show_action"
            phx-value-action="decline"
          >
            {gettext("Decline")}
          </.button>
          <.button
            :if={@can_manage and @order.status in [:sent, :declined]}
            phx-click="revise"
          >
            {gettext("Revise")}
          </.button>
          <.button
            :if={@can_manage and :in_production in Order.next_statuses(@order.status)}
            variant="primary"
            phx-click="transition"
            phx-value-status="in_production"
          >
            {gettext("Start production")}
          </.button>
          <.button
            :if={@can_manage and @order.status == :in_production and @all_done}
            variant="primary"
            phx-click="complete"
            data-confirm={gettext("Complete this order and consume material stock?")}
          >
            {gettext("Complete")}
          </.button>
          <.button
            :if={@can_manage and :cancelled in Order.next_statuses(@order.status)}
            phx-click="transition"
            phx-value-status="cancelled"
            data-confirm={gettext("Cancel this?")}
          >
            {gettext("Cancel")}
          </.button>
          <.button
            :if={
              @can_manage and @order.status in [:declined, :cancelled] and is_nil(@order.archived_at)
            }
            phx-click="show_action"
            phx-value-action="archive"
          >
            {gettext("Archive")}
          </.button>
        </:actions>
      </.header>

      <section
        :if={@pending_action == :decline}
        class="rounded-xl border border-error/40 bg-base-100 p-6"
      >
        <h2 class="mb-2 text-base font-semibold">{gettext("Decline quote")}</h2>
        <.form
          for={%{}}
          id="decline-form"
          phx-submit="decline"
          class="grid items-end gap-3 sm:grid-cols-3"
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
          <div class="flex gap-2">
            <.button variant="primary">{gettext("Decline")}</.button>
            <.button type="button" phx-click="cancel_action">{gettext("Cancel")}</.button>
          </div>
        </.form>
      </section>

      <section
        :if={@pending_action == :archive}
        class="rounded-xl border border-base-300 bg-base-100 p-6"
      >
        <h2 class="mb-2 text-base font-semibold">{gettext("Archive")}</h2>
        <.form
          for={%{}}
          id="archive-form"
          phx-submit="archive"
          class="grid items-end gap-3 sm:grid-cols-3"
        >
          <.input name="archive_reason" value="" type="text" label={gettext("Reason for archiving")} />
          <div class="flex gap-2">
            <.button variant="primary">{gettext("Archive")}</.button>
            <.button type="button" phx-click="cancel_action">{gettext("Cancel")}</.button>
          </div>
        </.form>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4">
          <.field label={gettext("Customer")} value={@order.relation.name} />
          <.field label={gettext("Quote number")} value={@order.quote_number} />
          <.field :if={@order.number} label={gettext("Order number")} value={@order.number} />
          <.field label={gettext("Reference")} value={@order.reference} />
          <.field label={gettext("Order date")} value={@order.order_date} />
          <.field label={gettext("Due date")} value={@order.due_date} />
          <.field :if={@order.valid_until} label={gettext("Valid until")} value={@order.valid_until} />
          <.field label={gettext("Total price")} value={money(@totals.price)} />
          <.field label={gettext("Total cost")} value={money(@totals.cost)} />
          <.field label={gettext("Total margin")} value={money(@totals.margin)} />
        </dl>
        <p
          :if={@order.status == :declined}
          class="mt-4 border-t border-base-200 pt-3 text-sm text-error"
        >
          {gettext("Declined")}: {status_label(@order.decline_reason)}{decline_notes_suffix(@order)}
        </p>
        <p :if={@order.archived_at} class="mt-2 text-sm text-base-content/60">
          {gettext("Archived")}: {@order.archive_reason}
        </p>
        <p :if={@order.notes} class="mt-4 whitespace-pre-line border-t border-base-200 pt-3 text-sm">
          {@order.notes}
        </p>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-3 text-base font-semibold">{gettext("Lines")}</h2>

        <p :if={@order.lines == []} class="text-sm text-base-content/60">
          {gettext("No lines yet.")}
        </p>

        <div :for={{line, depth} <- ordered_lines(@order.lines)} class="mb-2" style={indent(depth)}>
          <div
            :if={depends?(line)}
            class="mb-0.5 flex items-center gap-1 text-xs text-base-content/50"
          >
            <span class="text-base-content/40">&#8627;</span>
            {gettext("waits for %{names}", names: dependency_names(line))}
          </div>
          <.link
            navigate={~p"/orders/#{@order}/lines/#{line}"}
            class="flex items-center justify-between gap-4 rounded-lg border border-base-200 p-3 hover:bg-base-200/40"
          >
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span class="font-medium">{qty(line.quantity)} {line.output_unit}</span>
              <span>{line.description}</span>
              <span :if={materials_summary(line) != ""} class="text-sm text-base-content/60">
                · {materials_summary(line)}
              </span>
            </div>
            <div class="flex items-center gap-3">
              <span class={["badge badge-sm", step_status_class(Orders.line_status(line))]}>
                {status_label(Orders.line_status(line))}
              </span>
              <span class="text-sm font-medium">{money(line.total_price)}</span>
            </div>
          </.link>
        </div>

        <.form
          :if={@can_edit}
          for={%{}}
          id="add-line-form"
          phx-submit="add_line"
          class="mt-3 grid items-end gap-3 sm:grid-cols-3"
        >
          <.input
            name="product_template_id"
            value={@add_line["product_template_id"]}
            type="select"
            label={gettext("Add product")}
            prompt={gettext("Choose a product")}
            options={@template_options}
          />
          <.input
            name="quantity"
            value={@add_line["quantity"]}
            type="number"
            step="1"
            min="0"
            label={gettext("Quantity")}
          />
          <div>
            <.button variant="primary" phx-disable-with={gettext("Adding...")}>
              {gettext("Add line")}
            </.button>
          </div>
        </.form>

        <.form
          :if={@can_edit}
          for={%{}}
          id="add-custom-line-form"
          phx-submit="add_blank_line"
          class="mt-3 grid items-end gap-3 border-t border-base-200 pt-3 sm:grid-cols-4"
        >
          <.input
            name="description"
            value=""
            type="text"
            label={gettext("Custom line")}
            placeholder={gettext("Description")}
          />
          <.input name="output_unit" value="" type="text" label={gettext("Unit")} />
          <.input
            name="quantity"
            value="1"
            type="number"
            step="1"
            min="0"
            label={gettext("Quantity")}
          />
          <.input
            name="unit_price"
            value=""
            type="number"
            step="0.01"
            min="0"
            label={gettext("Manual price (optional)")}
          />
          <div class="sm:col-span-4">
            <.button phx-disable-with={gettext("Adding...")}>{gettext("Add custom line")}</.button>
          </div>
        </.form>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-3 text-base font-semibold">{gettext("Deliveries")}</h2>

        <p :if={@order.deliveries == []} class="text-sm text-base-content/60">
          {gettext("No delivery addresses yet.")}
        </p>

        <div :for={delivery <- @order.deliveries} class="mb-4 rounded-lg border border-base-200 p-4">
          <div class="flex items-start justify-between gap-4">
            <div class="text-sm">
              <div class="font-medium">{format_address(delivery)}</div>
              <div :if={delivery.planned_date} class="text-base-content/60">
                {gettext("Planned")}: {delivery.planned_date}
              </div>
            </div>
            <.link
              :if={@can_edit}
              phx-click="delete_delivery"
              phx-value-id={delivery.id}
              data-confirm={gettext("Remove this delivery?")}
              class="text-sm text-error"
            >
              {gettext("Remove")}
            </.link>
          </div>

          <.form
            :if={delivery.items != []}
            for={%{}}
            id={"delivery-items-#{delivery.id}"}
            phx-submit="save_delivery_items"
            class="mt-3 space-y-1"
          >
            <div :for={item <- delivery.items} class="flex items-center gap-2 text-sm">
              <span class="flex-1">{line_description(@order, item.order_line_id)}</span>
              <input
                :if={@can_edit}
                type="number"
                step="any"
                min="0"
                name={"items[#{item.id}]"}
                value={qty(item.quantity)}
                class="input input-sm w-28"
              />
              <span :if={not @can_edit}>{qty(item.quantity)}</span>
            </div>
            <.button :if={@can_edit} class="mt-1">{gettext("Save quantities")}</.button>
          </.form>
        </div>

        <.form
          :if={@can_edit}
          for={%{}}
          id="add-delivery-form"
          phx-submit="add_delivery"
          class="mt-2 grid items-end gap-3 border-t border-base-200 pt-3 sm:grid-cols-3"
        >
          <.input
            :if={@address_options != []}
            name="address_id"
            value=""
            type="select"
            label={gettext("Customer address")}
            prompt={gettext("— or type a new one below —")}
            options={@address_options}
          />
          <.input name="street" value="" type="text" label={gettext("Street")} />
          <.input name="postal_code" value="" type="text" label={gettext("Postal code")} />
          <.input name="city" value="" type="text" label={gettext("City")} />
          <.input name="country" value="" type="text" label={gettext("Country")} />
          <.input name="planned_date" value="" type="date" label={gettext("Planned date")} />
          <label class="flex items-center gap-2 text-sm">
            <input type="hidden" name="save_to_customer" value="false" />
            <input type="checkbox" name="save_to_customer" value="true" class="checkbox checkbox-sm" />
            {gettext("Save address to customer")}
          </label>
          <div class="sm:col-span-3">
            <.button phx-disable-with={gettext("Adding...")}>{gettext("Add delivery")}</.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  ## Events

  @impl true
  def handle_event("transition", %{"status" => status}, socket) do
    authorize(socket, fn ->
      case Orders.transition_order(socket.assigns.order, String.to_existing_atom(status)) do
        {:ok, _order} ->
          {:noreply, reload(socket, gettext("Order updated."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("That change is not allowed."))}
      end
    end)
  end

  def handle_event("complete", _params, socket) do
    authorize(socket, fn ->
      case Orders.complete_order(socket.assigns.order, socket.assigns.current_scope.user) do
        {:ok, _order} ->
          {:noreply, reload(socket, gettext("Order completed; stock consumed."))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, complete_error(reason))}
      end
    end)
  end

  def handle_event("send", _params, socket) do
    authorize(socket, fn ->
      case Orders.send_quote(socket.assigns.order, &url(~p"/quote/#{&1}")) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Quote emailed to the customer."))}

        {:error, :no_email} ->
          {:noreply, put_flash(socket, :error, gettext("The customer has no email address."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not send the quote."))}
      end
    end)
  end

  def handle_event("accept", _params, socket) do
    authorize(socket, fn ->
      case Orders.accept_quote(socket.assigns.order) do
        {:ok, order} ->
          {:noreply,
           reload(socket, gettext("Quote accepted — order %{n} created.", n: order.number))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not accept the quote."))}
      end
    end)
  end

  def handle_event("revise", _params, socket) do
    authorize(socket, fn ->
      case Orders.revise_quote(socket.assigns.order) do
        {:ok, _} -> {:noreply, reload(socket, gettext("Back to draft — adjust and re-send."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not revise."))}
      end
    end)
  end

  def handle_event("show_action", %{"action" => action}, socket) do
    {:noreply, assign(socket, :pending_action, String.to_existing_atom(action))}
  end

  def handle_event("cancel_action", _params, socket) do
    {:noreply, assign(socket, :pending_action, nil)}
  end

  def handle_event("decline", params, socket) do
    authorize(socket, fn ->
      case Orders.decline_quote(socket.assigns.order, params) do
        {:ok, _} -> {:noreply, reload(socket, gettext("Quote declined."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Choose a decline reason."))}
      end
    end)
  end

  def handle_event("archive", %{"archive_reason" => reason}, socket) do
    authorize(socket, fn ->
      case Orders.archive_order(socket.assigns.order, reason) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Archived."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("A reason is required to archive."))}
      end
    end)
  end

  def handle_event("add_line", %{"product_template_id" => "", "quantity" => _}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Choose a product first."))}
  end

  def handle_event("add_line", %{"product_template_id" => template_id, "quantity" => qty}, socket) do
    authorize(socket, fn ->
      case Orders.add_line_from_template(socket.assigns.order, template_id, qty) do
        {:ok, _line} -> {:noreply, reload(socket, gettext("Line added."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not add the line."))}
      end
    end)
  end

  def handle_event("add_blank_line", params, socket) do
    authorize(socket, fn ->
      case Orders.add_blank_line(socket.assigns.order, params) do
        {:ok, _line} ->
          {:noreply, reload(socket, gettext("Custom line added."))}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, gettext("A description and quantity are required."))}
      end
    end)
  end

  def handle_event("add_delivery", params, socket) do
    authorize(socket, fn ->
      case Orders.add_delivery(socket.assigns.order, params) do
        {:ok, _} ->
          {:noreply, reload(socket, gettext("Delivery added."))}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, gettext("Pick an address or enter a street and city."))}
      end
    end)
  end

  def handle_event("delete_delivery", %{"id" => id}, socket) do
    authorize(socket, fn ->
      case Orders.get_delivery!(id) |> Orders.delete_delivery() do
        {:ok, _} -> {:noreply, reload(socket, gettext("Delivery removed."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not remove it."))}
      end
    end)
  end

  def handle_event("save_delivery_items", %{"items" => items}, socket) do
    authorize(socket, fn ->
      Enum.each(items, fn {item_id, quantity} ->
        Orders.get_delivery_item!(item_id) |> Orders.update_delivery_item(quantity)
      end)

      {:noreply, reload(socket, gettext("Quantities saved."))}
    end)
  end

  defp authorize(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  defp complete_error(:steps_unfinished), do: gettext("Every route step must be done first.")
  defp complete_error(:not_in_production), do: gettext("The order is not in production.")
  defp complete_error(_), do: gettext("Could not complete the order.")

  defp back_path(order), do: if(Order.quote?(order), do: ~p"/quotes", else: ~p"/orders")

  defp back_label(order),
    do: if(Order.quote?(order), do: gettext("All quotes"), else: gettext("All orders"))

  defp decline_reason_options do
    Enum.map(Order.decline_reasons(), &{status_label(&1), to_string(&1)})
  end

  defp decline_notes_suffix(%{decline_notes: notes}) when notes not in [nil, ""],
    do: " — #{notes}"

  defp decline_notes_suffix(_order), do: ""

  defp template_options do
    Catalog.list_product_templates() |> Enum.map(&{&1.name, &1.id})
  end

  defp materials_summary(line) do
    line.materials |> Enum.map(& &1.material_name) |> Enum.join(", ")
  end

  defp depends?(%{depends_on: deps}) when is_list(deps), do: deps != []
  defp depends?(_line), do: false

  defp dependency_names(%{depends_on: deps}) when is_list(deps),
    do: deps |> Enum.map(& &1.description) |> Enum.join(", ")

  defp indent(0), do: nil
  defp indent(depth), do: "margin-left: #{depth * 1.5}rem"

  # Orders lines so a line always appears below (and indented under) the line(s)
  # it depends on. Returns [{line, depth}]; depth = longest dependency chain.
  defp ordered_lines(lines) do
    by_id = Map.new(lines, &{&1.id, &1})
    depth = Enum.reduce(lines, %{}, &line_depth(&1, by_id, &2, MapSet.new()))
    dependents = dependents_map(lines)
    roots = Enum.filter(lines, &(&1.depends_on == []))

    {ordered, emitted} =
      Enum.reduce(roots, {[], MapSet.new()}, &emit_line(&1, dependents, depth, &2))

    # Any line not reached (e.g. a dependency cycle) is appended as-is.
    remaining =
      lines
      |> Enum.reject(&MapSet.member?(emitted, &1.id))
      |> Enum.map(&{&1, Map.get(depth, &1.id, 0)})

    Enum.reverse(ordered) ++ remaining
  end

  defp emit_line(line, dependents, depth, {acc, emitted}) do
    cond do
      MapSet.member?(emitted, line.id) ->
        {acc, emitted}

      not Enum.all?(line.depends_on, &MapSet.member?(emitted, &1.id)) ->
        {acc, emitted}

      true ->
        acc = [{line, Map.get(depth, line.id, 0)} | acc]
        emitted = MapSet.put(emitted, line.id)
        children = Map.get(dependents, line.id, [])
        Enum.reduce(children, {acc, emitted}, &emit_line(&1, dependents, depth, &2))
    end
  end

  defp dependents_map(lines) do
    for child <- lines, parent <- child.depends_on, reduce: %{} do
      acc -> Map.update(acc, parent.id, [child], &(&1 ++ [child]))
    end
  end

  defp line_depth(line, by_id, acc, visiting) do
    cond do
      Map.has_key?(acc, line.id) -> acc
      MapSet.member?(visiting, line.id) -> Map.put(acc, line.id, 0)
      line.depends_on == [] -> Map.put(acc, line.id, 0)
      true -> compute_depth(line, by_id, acc, visiting)
    end
  end

  defp compute_depth(line, by_id, acc, visiting) do
    visiting = MapSet.put(visiting, line.id)
    acc = Enum.reduce(line.depends_on, acc, &line_depth(by_id[&1.id] || &1, by_id, &2, visiting))
    d = line.depends_on |> Enum.map(&Map.get(acc, &1.id, 0)) |> Enum.max() |> Kernel.+(1)
    Map.put(acc, line.id, d)
  end

  defp format_address(%{street: street, postal_code: postal, city: city, country: country}) do
    [street, [postal, city] |> Enum.reject(&blank?/1) |> Enum.join(" "), country]
    |> Enum.reject(&blank?/1)
    |> Enum.join(", ")
  end

  defp blank?(value), do: value in [nil, ""]

  defp qty(%Decimal{} = d), do: Decimal.to_string(Decimal.normalize(d), :normal)

  defp line_description(order, line_id) do
    case Enum.find(order.lines, &(&1.id == line_id)) do
      nil -> gettext("Line")
      line -> line.description
    end
  end
end
