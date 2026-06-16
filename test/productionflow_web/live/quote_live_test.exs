defmodule ProductionflowWeb.QuoteLiveTest do
  use ProductionflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Productionflow.CRMFixtures
  import Productionflow.OrdersFixtures

  alias Productionflow.Orders

  defp sent_quote_token(email \\ "buyer@example.com") do
    order = order_fixture(relation_fixture(%{name: "Buyer", email: email}))

    {:ok, _} =
      Orders.send_quote(order, fn t ->
        send(self(), {:token, t})
        "http://x/quote/#{t}"
      end)

    assert_received {:token, token}
    {order, token}
  end

  test "an invalid token shows an unavailable message", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/quote/nope")
    assert html =~ "invalid or has expired"
  end

  test "a customer can accept a quote (no login)", %{conn: conn} do
    {order, token} = sent_quote_token()

    {:ok, lv, html} = live(conn, ~p"/quote/#{token}")
    assert html =~ order.quote_number

    lv |> element("button", "Accept quote") |> render_click()

    assert Orders.get_order!(order.id).status == :accepted
    assert render(lv) =~ "accepted"
  end

  test "a customer can decline with a reason", %{conn: conn} do
    {order, token} = sent_quote_token()

    {:ok, lv, _html} = live(conn, ~p"/quote/#{token}")
    lv |> element("button", "Decline") |> render_click()

    lv
    |> form("#public-decline-form", %{decline_reason: "price", decline_notes: "too high"})
    |> render_submit()

    declined = Orders.get_order!(order.id)
    assert declined.status == :declined
    assert declined.decline_reason == :price
  end
end
