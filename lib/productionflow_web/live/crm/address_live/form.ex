defmodule ProductionflowWeb.CRM.AddressLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.CRM
  alias Productionflow.CRM.Address

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@relation.name}</:subtitle>
      </.header>

      <.form for={@form} id="address-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:kind]}
          type="select"
          label={gettext("Type")}
          options={kind_options()}
        />
        <.input field={@form[:street]} type="text" label={gettext("Street")} required />
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:postal_code]} type="text" label={gettext("Postal code")} />
          <.input field={@form[:city]} type="text" label={gettext("City")} required />
        </div>
        <.input field={@form[:country]} type="text" label={gettext("Country")} />
        <.input field={@form[:is_default]} type="checkbox" label={gettext("Default address")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save address")}
          </.button>
          <.button navigate={~p"/relations/#{@relation}"}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    relation = CRM.get_relation!(params["id"])

    {:ok,
     socket |> assign(:relation, relation) |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New address"))
    |> assign(:address, %Address{})
    |> assign_form(CRM.change_address(%Address{}))
  end

  defp apply_action(socket, :edit, %{"address_id" => address_id}) do
    address = CRM.get_address!(address_id)

    socket
    |> assign(:page_title, gettext("Edit address"))
    |> assign(:address, address)
    |> assign_form(CRM.change_address(address))
  end

  @impl true
  def handle_event("validate", %{"address" => params}, socket) do
    changeset = CRM.change_address(socket.assigns.address, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"address" => params}, socket) do
    save_address(socket, socket.assigns.live_action, params)
  end

  defp save_address(socket, :new, params) do
    case CRM.create_address(socket.assigns.relation, params) do
      {:ok, _address} -> saved(socket, gettext("Address added."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_address(socket, :edit, params) do
    case CRM.update_address(socket.assigns.address, params) do
      {:ok, _address} -> saved(socket, gettext("Address updated."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp saved(socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/relations/#{socket.assigns.relation}")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "address"))
  end

  defp kind_options do
    Enum.map(Address.kinds(), &{Phoenix.Naming.humanize(&1), &1})
  end
end
