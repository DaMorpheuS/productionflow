defmodule Productionflow.Orders.OrderLine do
  use Ecto.Schema
  import Ecto.Changeset

  @price_sources [:calculated, :price_list, :manual]

  schema "order_lines" do
    field :position, :integer, default: 0
    field :description, :string
    field :output_unit, :string
    field :quantity, :decimal

    # Price/cost/margin snapshots, frozen once the order leaves :draft.
    field :unit_price, :decimal
    field :total_price, :decimal
    field :internal_unit_cost, :decimal
    field :internal_total_cost, :decimal
    field :unit_margin, :decimal
    field :total_margin, :decimal
    field :price_source, Ecto.Enum, values: @price_sources

    belongs_to :order, Productionflow.Orders.Order
    belongs_to :product_template, Productionflow.Catalog.ProductTemplate

    has_many :route_steps, Productionflow.Orders.OrderRouteStep,
      preload_order: [asc: :position, asc: :id]

    has_many :materials, Productionflow.Orders.OrderLineMaterial

    many_to_many :depends_on, __MODULE__,
      join_through: "order_line_dependencies",
      join_keys: [order_line_id: :id, depends_on_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc "True when this line has no product template — its route is built ad-hoc."
  def ad_hoc?(%__MODULE__{product_template_id: nil}), do: true
  def ad_hoc?(%__MODULE__{}), do: false

  @doc "The price-source values."
  def price_sources, do: @price_sources

  @doc false
  def changeset(line, attrs) do
    line
    |> cast(attrs, [:description, :output_unit, :quantity])
    |> validate_required([:description, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
