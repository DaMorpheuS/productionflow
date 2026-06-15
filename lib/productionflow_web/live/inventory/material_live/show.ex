defmodule ProductionflowWeb.Inventory.MaterialLive.Show do
  use ProductionflowWeb, :live_view

  alias Productionflow.Inventory
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    material = Inventory.get_material!(id)

    {:ok,
     socket
     |> assign(:page_title, material.name)
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "inventory.manage"))
     |> assign(:can_book, Scope.can?(socket.assigns.current_scope, "inventory.book"))
     |> assign(:booking_kind, "purchase")
     |> assign(:adjust_mode, "set")
     |> assign_material(material)}
  end

  defp assign_material(socket, material) do
    socket
    |> assign(:material, material)
    |> stream(:movements, material.movements, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@material.name}
        <span :if={@material.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        <:subtitle>
          <.link navigate={~p"/inventory/materials"} class="hover:underline">
            &larr; {gettext("All materials")}
          </.link>
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/inventory/materials/#{@material}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button :if={@can_manage and is_nil(@material.archived_at)} phx-click="archive">
            {gettext("Archive")}
          </.button>
          <.button :if={@can_manage and @material.archived_at} phx-click="unarchive">
            {gettext("Unarchive")}
          </.button>
        </:actions>
      </.header>

      <div class="rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="mb-3 flex items-center gap-2">
          <span class="text-2xl font-semibold">
            {Decimal.to_string(@material.current_stock)} {@material.unit}
          </span>
          <span :if={Inventory.negative_stock?(@material)} class="badge badge-error">
            {gettext("Negative stock")}
          </span>
          <span :if={Inventory.low_stock?(@material)} class="badge badge-warning">
            {gettext("Low stock")}
          </span>
        </div>
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <.detail label={gettext("SKU")} value={@material.sku} />
          <.detail label={gettext("Supplier code")} value={@material.supplier_code} />
          <.detail label={gettext("Category")} value={@material.category && @material.category.name} />
          <.detail label={gettext("Supplier")} value={@material.supplier && @material.supplier.name} />
          <.detail label={gettext("Cost price")} value={money(@material.cost_price)} />
          <.detail label={gettext("Sales price")} value={money(@material.sales_price)} />
          <.detail
            :if={@material.minimum_stock}
            label={gettext("Minimum stock")}
            value={Decimal.to_string(@material.minimum_stock)}
          />
          <.detail
            :if={@material.material_type}
            label={gettext("Type")}
            value={@material.material_type.name}
          />
        </dl>

        <div :if={@material.material_type} class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            {@material.material_type.name}
          </p>
          <dl class="mt-1 grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
            <.detail
              :for={definition <- @material.material_type.field_definitions}
              label={field_label(definition)}
              value={attribute_display(@material.attributes, definition)}
            />
          </dl>
        </div>
      </div>

      <section :if={@can_book} class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Book stock movement")}</h2>
        <.form
          for={%{}}
          id="booking-form"
          phx-change="booking_change"
          phx-submit="book"
          class="flex flex-wrap items-end gap-3"
        >
          <label class="text-sm">
            <span class="block">{gettext("Type")}</span>
            <select name="kind" class="select">
              <option value="purchase" selected={@booking_kind == "purchase"}>
                {gettext("Purchase (add)")}
              </option>
              <option value="consumption" selected={@booking_kind == "consumption"}>
                {gettext("Consumption (remove)")}
              </option>
              <option value="adjustment" selected={@booking_kind == "adjustment"}>
                {gettext("Adjustment")}
              </option>
            </select>
          </label>

          <label :if={@booking_kind == "adjustment"} class="text-sm">
            <span class="block">{gettext("Mode")}</span>
            <select name="mode" class="select">
              <option value="set" selected={@adjust_mode == "set"}>
                {gettext("Set to counted")}
              </option>
              <option value="delta" selected={@adjust_mode == "delta"}>{gettext("Delta +/−")}</option>
            </select>
          </label>

          <label class="text-sm">
            <span class="block">{quantity_label(@booking_kind, @adjust_mode)}</span>
            <input type="number" name="quantity" step="0.01" class="input" required />
          </label>

          <label :if={@booking_kind == "purchase"} class="text-sm">
            <span class="block">{gettext("Unit cost (€)")}</span>
            <input type="number" name="unit_cost" step="0.01" class="input" />
          </label>

          <label class="text-sm">
            <span class="block">{gettext("Note")}</span>
            <input type="text" name="note" class="input" />
          </label>

          <.button variant="primary">{gettext("Book")}</.button>
        </.form>
      </section>

      <section class="rounded-xl border border-base-300 bg-base-100 p-6">
        <h2 class="mb-2 text-base font-semibold">{gettext("Stock movements")}</h2>
        <ul id="movements" phx-update="stream" class="divide-y divide-base-200">
          <li id="movements-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No movements yet.")}
          </li>
          <li
            :for={{id, mv} <- @streams.movements}
            id={id}
            class="flex items-center gap-4 py-2 text-sm"
          >
            <span class="w-28 text-base-content/60">
              {Calendar.strftime(mv.inserted_at, "%Y-%m-%d %H:%M")}
            </span>
            <span class="badge badge-sm">{kind_label(mv.kind)}</span>
            <span class={["w-24 font-semibold", signed_class(mv.quantity)]}>
              {signed(mv.quantity)}
            </span>
            <span class="flex-1 text-base-content/70">{mv.note}</span>
            <span class="text-base-content/50">{mv.user && mv.user.email}</span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp detail(assigns) do
    ~H"""
    <div :if={@value}>
      <dt class="text-xs text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  ## Events

  @impl true
  def handle_event("booking_change", params, socket) do
    {:noreply,
     socket
     |> assign(:booking_kind, params["kind"] || socket.assigns.booking_kind)
     |> assign(:adjust_mode, params["mode"] || socket.assigns.adjust_mode)}
  end

  def handle_event("book", params, socket) do
    authorize_book(socket, fn ->
      material = socket.assigns.material
      user = socket.assigns.current_scope.user
      before = material.current_stock

      result =
        case params["kind"] do
          "purchase" ->
            Inventory.receive_stock(material, user, %{
              quantity: params["quantity"],
              unit_cost: params["unit_cost"],
              note: params["note"]
            })

          "consumption" ->
            Inventory.consume(material, user, %{
              quantity: params["quantity"],
              note: params["note"]
            })

          "adjustment" ->
            Inventory.adjust(material, user, %{
              mode: params["mode"] || "set",
              quantity: params["quantity"],
              note: params["note"]
            })
        end

      case result do
        {:ok, updated} ->
          reloaded = Inventory.get_material!(updated.id)
          flash = booking_flash(before, reloaded.current_stock)
          {:noreply, socket |> put_flash(:info, flash) |> assign_material(reloaded)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not book the movement."))}
      end
    end)
  end

  def handle_event("archive", _params, socket) do
    authorize_manage(socket, fn ->
      {:ok, material} = Inventory.archive_material(socket.assigns.material)

      {:noreply,
       socket |> assign(:material, material) |> put_flash(:info, gettext("Material archived."))}
    end)
  end

  def handle_event("unarchive", _params, socket) do
    authorize_manage(socket, fn ->
      {:ok, material} = Inventory.unarchive_material(socket.assigns.material)

      {:noreply,
       socket |> assign(:material, material) |> put_flash(:info, gettext("Material restored."))}
    end)
  end

  defp booking_flash(before, after_stock) do
    if Decimal.equal?(before, after_stock),
      do: gettext("Stock already at that amount; no change recorded."),
      else: gettext("Movement booked.")
  end

  defp authorize_book(socket, fun) do
    if socket.assigns.can_book,
      do: fun.(),
      else:
        {:noreply,
         put_flash(socket, :error, gettext("You are not authorized to book movements."))}
  end

  defp authorize_manage(socket, fun) do
    if socket.assigns.can_manage,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
  end

  ## Helpers

  defp quantity_label("adjustment", "set"), do: gettext("Counted amount")
  defp quantity_label("adjustment", _), do: gettext("Delta (+/−)")
  defp quantity_label(_kind, _mode), do: gettext("Quantity")

  defp kind_label(:purchase), do: gettext("Purchase")
  defp kind_label(:consumption), do: gettext("Consumption")
  defp kind_label(:adjustment), do: gettext("Adjustment")

  defp signed(%Decimal{} = q) do
    if Decimal.compare(q, 0) == :lt, do: Decimal.to_string(q), else: "+#{Decimal.to_string(q)}"
  end

  defp signed_class(%Decimal{} = q) do
    if Decimal.compare(q, 0) == :lt, do: "text-error", else: "text-success"
  end

  defp field_label(%{label: label, unit: unit}) when unit not in [nil, ""],
    do: "#{label} (#{unit})"

  defp field_label(%{label: label}), do: label

  defp attribute_display(attributes, %{key: key, field_type: :boolean}) do
    case Map.get(attributes, key) do
      true -> gettext("Yes")
      false -> gettext("No")
      _ -> nil
    end
  end

  defp attribute_display(attributes, %{key: key}) do
    case Map.get(attributes, key) do
      value when value in [nil, ""] -> nil
      value -> to_string(value)
    end
  end
end
