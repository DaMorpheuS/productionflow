defmodule Productionflow.Orders.OrderNotifier do
  @moduledoc "Customer-facing emails for the Orders context (quote delivery)."

  import Swoosh.Email

  alias Productionflow.Mailer

  @doc "Emails the customer a link to review and accept/decline a quote."
  def deliver_quote(order, recipient, url) do
    deliver(recipient, "Your quote #{order.quote_number}", """

    Hi #{order.relation.name},

    Please review your quote #{order.quote_number} and let us know whether you
    accept it by visiting the link below:

    #{url}

    Thank you.
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Productionflow", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
