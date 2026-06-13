defmodule ProductionflowWeb.CRM.RelationLive.Form do
  use ProductionflowWeb, :live_view

  alias Productionflow.CRM
  alias Productionflow.CRM.Relation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="relation-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} required />
        <.input field={@form[:code]} type="text" label={gettext("Code")} />

        <fieldset class="mt-4">
          <legend class="text-sm font-semibold">{gettext("Type")}</legend>
          <div class="mt-2 flex flex-wrap gap-4">
            <.input field={@form[:is_customer]} type="checkbox" label={gettext("Customer")} />
            <.input field={@form[:is_supplier]} type="checkbox" label={gettext("Supplier")} />
            <.input field={@form[:is_prospect]} type="checkbox" label={gettext("Prospect")} />
          </div>
        </fieldset>

        <div class="mt-4 grid gap-4 sm:grid-cols-2">
          <.input field={@form[:email]} type="email" label={gettext("Email")} />
          <.input field={@form[:phone]} type="text" label={gettext("Phone")} />
          <.input field={@form[:website]} type="text" label={gettext("Website")} />
          <.input field={@form[:vat_number]} type="text" label={gettext("VAT number")} />
          <.input field={@form[:iban]} type="text" label={gettext("IBAN")} />
        </div>

        <.input field={@form[:remarks]} type="textarea" label={gettext("Remarks")} />

        <div class="mt-6 flex items-center gap-3">
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save relation")}
          </.button>
          <.button navigate={cancel_path(@relation)}>{gettext("Cancel")}</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    relation = %Relation{}

    socket
    |> assign(:page_title, gettext("New relation"))
    |> assign(:relation, relation)
    |> assign_form(CRM.change_relation(relation))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    relation = CRM.get_relation!(id)

    socket
    |> assign(:page_title, gettext("Edit relation"))
    |> assign(:relation, relation)
    |> assign_form(CRM.change_relation(relation))
  end

  @impl true
  def handle_event("validate", %{"relation" => params}, socket) do
    changeset = CRM.change_relation(socket.assigns.relation, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"relation" => params}, socket) do
    save_relation(socket, socket.assigns.live_action, params)
  end

  defp save_relation(socket, :new, params) do
    case CRM.create_relation(params) do
      {:ok, relation} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Relation created."))
         |> push_navigate(to: ~p"/relations/#{relation}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_relation(socket, :edit, params) do
    case CRM.update_relation(socket.assigns.relation, params) do
      {:ok, relation} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Relation updated."))
         |> push_navigate(to: ~p"/relations/#{relation}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "relation"))
  end

  defp cancel_path(%Relation{id: nil}), do: ~p"/relations"
  defp cancel_path(relation), do: ~p"/relations/#{relation}"
end
