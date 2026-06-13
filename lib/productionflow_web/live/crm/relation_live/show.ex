defmodule ProductionflowWeb.CRM.RelationLive.Show do
  use ProductionflowWeb, :live_view

  alias Productionflow.CRM
  alias Productionflow.CRM.Note
  alias Productionflow.Accounts.Scope

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    relation = CRM.get_relation!(id)

    {:ok,
     socket
     |> assign(:page_title, relation.name)
     |> assign(:can_manage, Scope.can?(socket.assigns.current_scope, "crm.manage"))
     |> assign_relation(relation)
     |> assign(:note_form, note_form())}
  end

  defp assign_relation(socket, relation) do
    socket
    |> assign(:relation, relation)
    |> stream(:addresses, relation.addresses, reset: true)
    |> stream(:contacts, relation.contacts, reset: true)
    |> stream(:notes, relation.notes, reset: true)
  end

  defp note_form(params \\ %{}), do: to_form(CRM.change_note(%Note{}, params), as: "note")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>
        {@relation.name}
        <span :if={@relation.archived_at} class="badge badge-ghost ml-2">{gettext("Archived")}</span>
        <:subtitle>
          <.link navigate={~p"/relations"} class="hover:underline">
            &larr; {gettext("All relations")}
          </.link>
        </:subtitle>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/relations/#{@relation}/edit"}>
            {gettext("Edit")}
          </.button>
          <.button :if={@can_manage and is_nil(@relation.archived_at)} phx-click="archive">
            {gettext("Archive")}
          </.button>
          <.button :if={@can_manage and @relation.archived_at} phx-click="unarchive">
            {gettext("Unarchive")}
          </.button>
        </:actions>
      </.header>

      <div class="rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="mb-3 flex flex-wrap gap-1">
          <span :if={@relation.is_customer} class="badge badge-primary">{gettext("Customer")}</span>
          <span :if={@relation.is_supplier} class="badge badge-secondary">
            {gettext("Supplier")}
          </span>
          <span :if={@relation.is_prospect} class="badge badge-accent">{gettext("Prospect")}</span>
        </div>
        <dl class="grid grid-cols-1 gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
          <.detail label={gettext("Code")} value={@relation.code} />
          <.detail label={gettext("Email")} value={@relation.email} />
          <.detail label={gettext("Phone")} value={@relation.phone} />
          <.detail label={gettext("Website")} value={@relation.website} />
          <.detail label={gettext("VAT number")} value={@relation.vat_number} />
          <.detail label={gettext("IBAN")} value={@relation.iban} />
        </dl>
        <div :if={@relation.remarks} class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            {gettext("Remarks")}
          </p>
          <p class="whitespace-pre-line text-sm">{@relation.remarks}</p>
        </div>
      </div>

      <.section_card title={gettext("Addresses")}>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/relations/#{@relation}/addresses/new"}>
            {gettext("Add address")}
          </.button>
        </:actions>
        <ul id="addresses" phx-update="stream" class="divide-y divide-base-200">
          <li id="addresses-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No addresses yet.")}
          </li>
          <li :for={{id, address} <- @streams.addresses} id={id} class="flex items-start gap-4 py-3">
            <div class="flex-1">
              <p class="text-sm font-medium">
                <span class="badge badge-sm mr-2">{address_kind_label(address.kind)}</span>
                <span :if={address.is_default} class="badge badge-success badge-sm mr-2">
                  {gettext("Default")}
                </span>
                {address_label(address)}
              </p>
            </div>
            <div :if={@can_manage} class="flex gap-3 text-sm">
              <.link navigate={~p"/relations/#{@relation}/addresses/#{address}/edit"}>
                {gettext("Edit")}
              </.link>
              <.link
                phx-click="delete_address"
                phx-value-id={address.id}
                data-confirm={gettext("Delete this address?")}
              >
                {gettext("Delete")}
              </.link>
            </div>
          </li>
        </ul>
      </.section_card>

      <.section_card title={gettext("Contacts")}>
        <:actions>
          <.button :if={@can_manage} navigate={~p"/relations/#{@relation}/contacts/new"}>
            {gettext("Add contact")}
          </.button>
        </:actions>
        <ul id="contacts" phx-update="stream" class="divide-y divide-base-200">
          <li id="contacts-empty" class="hidden py-3 text-sm text-base-content/60 only:block">
            {gettext("No contacts yet.")}
          </li>
          <li :for={{id, contact} <- @streams.contacts} id={id} class="flex items-start gap-4 py-3">
            <div class="flex-1">
              <p class="text-sm font-medium">
                {contact.name}
                <span :if={contact.job_title} class="text-base-content/60">
                  — {contact.job_title}
                </span>
              </p>
              <p class="text-sm text-base-content/70">
                {[contact.email, contact.phone] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")}
              </p>
              <p :if={contact.address} class="text-xs text-base-content/50">
                {gettext("Location")}: {address_label(contact.address)}
              </p>
            </div>
            <div :if={@can_manage} class="flex gap-3 text-sm">
              <.link navigate={~p"/relations/#{@relation}/contacts/#{contact}/edit"}>
                {gettext("Edit")}
              </.link>
              <.link
                phx-click="delete_contact"
                phx-value-id={contact.id}
                data-confirm={gettext("Delete this contact?")}
              >
                {gettext("Delete")}
              </.link>
            </div>
          </li>
        </ul>
      </.section_card>

      <.section_card title={gettext("Notes")}>
        <.form
          :if={@can_manage}
          for={@note_form}
          id="note-form"
          phx-submit="add_note"
          class="mb-4 flex gap-2"
        >
          <.input
            field={@note_form[:body]}
            type="textarea"
            placeholder={gettext("Add a note...")}
            class="textarea flex-1"
          />
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Add")}
          </.button>
        </.form>
        <ul id="notes" phx-update="stream" class="space-y-3">
          <li id="notes-empty" class="hidden text-sm text-base-content/60 only:block">
            {gettext("No notes yet.")}
          </li>
          <li :for={{id, note} <- @streams.notes} id={id} class="rounded-lg bg-base-200 p-3">
            <div class="flex items-center justify-between">
              <p class="text-xs text-base-content/60">
                {note.user && note.user.email} · {Calendar.strftime(
                  note.inserted_at,
                  "%Y-%m-%d %H:%M"
                )}
              </p>
              <.link
                :if={@can_manage}
                phx-click="delete_note"
                phx-value-id={note.id}
                data-confirm={gettext("Delete this note?")}
                class="text-xs"
              >
                {gettext("Delete")}
              </.link>
            </div>
            <p class="mt-1 whitespace-pre-line text-sm">{note.body}</p>
          </li>
        </ul>
      </.section_card>
    </Layouts.app>
    """
  end

  ## Components

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp detail(assigns) do
    ~H"""
    <div :if={@value}>
      <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :actions
  slot :inner_block, required: true

  defp section_card(assigns) do
    ~H"""
    <section class="rounded-xl border border-base-300 bg-base-100 p-6">
      <div class="mb-2 flex items-center justify-between">
        <h2 class="text-base font-semibold">{@title}</h2>
        <div>{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  ## Events

  @impl true
  def handle_event("archive", _params, socket) do
    authorize(socket, fn ->
      {:ok, relation} = CRM.archive_relation(socket.assigns.relation)

      {:noreply,
       socket |> assign(:relation, relation) |> put_flash(:info, gettext("Relation archived."))}
    end)
  end

  def handle_event("unarchive", _params, socket) do
    authorize(socket, fn ->
      {:ok, relation} = CRM.unarchive_relation(socket.assigns.relation)

      {:noreply,
       socket |> assign(:relation, relation) |> put_flash(:info, gettext("Relation restored."))}
    end)
  end

  def handle_event("delete_address", %{"id" => id}, socket) do
    authorize(socket, fn ->
      address = CRM.get_address!(id)
      {:ok, _} = CRM.delete_address(address)
      # Contacts may have had their location cleared, so reload the relation.
      relation = CRM.get_relation!(socket.assigns.relation.id)

      {:noreply,
       socket
       |> assign_relation(relation)
       |> put_flash(:info, gettext("Address deleted."))}
    end)
  end

  def handle_event("delete_contact", %{"id" => id}, socket) do
    authorize(socket, fn ->
      contact = CRM.get_contact!(id)
      {:ok, _} = CRM.delete_contact(contact)

      {:noreply,
       socket
       |> stream_delete(:contacts, contact)
       |> put_flash(:info, gettext("Contact deleted."))}
    end)
  end

  def handle_event("add_note", %{"note" => note_params}, socket) do
    authorize(socket, fn ->
      case CRM.create_note(
             socket.assigns.relation,
             socket.assigns.current_scope.user,
             note_params
           ) do
        {:ok, note} ->
          note = %{note | user: socket.assigns.current_scope.user}

          {:noreply,
           socket
           |> stream_insert(:notes, note, at: 0)
           |> assign(:note_form, note_form())}

        {:error, changeset} ->
          {:noreply, assign(socket, :note_form, to_form(changeset, as: "note"))}
      end
    end)
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    authorize(socket, fn ->
      note = Productionflow.Repo.get!(Note, id)
      {:ok, _} = CRM.delete_note(note)

      {:noreply,
       socket |> stream_delete(:notes, note) |> put_flash(:info, gettext("Note deleted."))}
    end)
  end

  # Server-side guard for the mutating events on this otherwise view-level page.
  defp authorize(socket, fun) do
    if socket.assigns.can_manage do
      fun.()
    else
      {:noreply, put_flash(socket, :error, gettext("You are not authorized to do that."))}
    end
  end

  ## Helpers

  defp address_kind_label(:invoice), do: gettext("Invoice")
  defp address_kind_label(:delivery), do: gettext("Delivery")
  defp address_kind_label(:visiting), do: gettext("Visiting")

  defp address_label(address) do
    [address.street, address.postal_code, address.city, address.country]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end
end
