defmodule ProductionflowWeb.CRM.ContactLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.CRM
  alias Productionflow.CRM.{Contact, Address}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@page_title}
        <:subtitle>{@relation.name}</:subtitle>
      </.header>

      <.form for={@form} id="contact-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} required />
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:job_title]} type="text" label={gettext("Job title")} />
          <.input field={@form[:email]} type="email" label={gettext("Email")} />
          <.input field={@form[:phone]} type="text" label={gettext("Phone")} />
        </div>
        <.input field={@form[:remarks]} type="textarea" label={gettext("Remarks")} />

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Location")}</legend>

          <div :if={not @new_location?} class="mt-2 flex items-end gap-3">
            <.input
              field={@form[:address_id]}
              type="select"
              label={gettext("Existing location")}
              prompt={gettext("No location")}
              options={@location_options}
              class="flex-1"
            />
            <.button type="button" phx-click="new_location">{gettext("New location")}</.button>
          </div>

          <div :if={@new_location?} class="mt-2 space-y-3 rounded-lg border border-base-300 p-4">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium">{gettext("New location")}</p>
              <.button type="button" phx-click="existing_location">
                {gettext("Pick existing")}
              </.button>
            </div>
            <.input
              field={@location_form[:kind]}
              type="select"
              label={gettext("Type")}
              options={kind_options()}
            />
            <.input field={@location_form[:street]} type="text" label={gettext("Street")} required />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@location_form[:postal_code]} type="text" label={gettext("Postal code")} />
              <.input field={@location_form[:city]} type="text" label={gettext("City")} required />
            </div>
            <.input field={@location_form[:country]} type="text" label={gettext("Country")} />
          </div>
        </fieldset>

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save contact")}
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
     socket
     |> assign(:relation, relation)
     |> assign(:new_location?, false)
     |> assign(:location_form, location_form())
     |> assign(:location_options, location_options(relation))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New contact"))
    |> assign(:contact, %Contact{})
    |> assign_form(CRM.change_contact(socket.assigns.relation, %Contact{}))
  end

  defp apply_action(socket, :edit, %{"contact_id" => contact_id}) do
    contact = CRM.get_contact!(contact_id)

    socket
    |> assign(:page_title, gettext("Edit contact"))
    |> assign(:contact, contact)
    |> assign_form(CRM.change_contact(socket.assigns.relation, contact))
  end

  @impl true
  def handle_event("new_location", _params, socket) do
    {:noreply, assign(socket, :new_location?, true)}
  end

  def handle_event("existing_location", _params, socket) do
    {:noreply, assign(socket, :new_location?, false)}
  end

  def handle_event("validate", %{"contact" => contact_params} = params, socket) do
    changeset =
      CRM.change_contact(socket.assigns.relation, socket.assigns.contact, contact_params)

    {:noreply,
     socket
     |> assign_form(Map.put(changeset, :action, :validate))
     |> assign(:location_form, location_form(params["location"] || %{}))}
  end

  def handle_event("save", %{"contact" => contact_params} = params, socket) do
    location_attrs = if socket.assigns.new_location?, do: params["location"], else: nil
    save_contact(socket, socket.assigns.live_action, contact_params, location_attrs)
  end

  defp save_contact(socket, :new, contact_params, location_attrs) do
    case CRM.create_contact(socket.assigns.relation, contact_params, location_attrs) do
      {:ok, _contact} -> saved(socket, gettext("Contact added."))
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_contact(socket, :edit, contact_params, location_attrs) do
    case CRM.update_contact(
           socket.assigns.relation,
           socket.assigns.contact,
           contact_params,
           location_attrs
         ) do
      {:ok, _contact} -> saved(socket, gettext("Contact updated."))
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
    assign(socket, :form, to_form(changeset, as: "contact"))
  end

  defp location_form(params \\ %{}) do
    to_form(Address.changeset(%Address{}, params), as: "location")
  end

  defp location_options(relation) do
    Enum.map(relation.addresses, &{address_label(&1), &1.id})
  end

  defp kind_options do
    Enum.map(Address.kinds(), &{Phoenix.Naming.humanize(&1), &1})
  end

  defp address_label(address) do
    [address.street, address.postal_code, address.city]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end
end
