defmodule ProductionflowWeb.PageController do
  use ProductionflowWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
