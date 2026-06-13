defmodule ProductionflowWeb.FormatsTest do
  use ExUnit.Case, async: true
  doctest ProductionflowWeb.Formats

  alias ProductionflowWeb.Formats

  test "money rounds to two decimals" do
    assert Formats.money(Decimal.new("4")) == "€4.00"
    assert Formats.money(Decimal.new("4.567")) == "€4.57"
    assert Formats.money(nil) == "—"
  end

  test "duration formats hours and minutes" do
    assert Formats.duration(Decimal.new("90")) == "1h 30m"
    assert Formats.duration(45) == "45m"
    assert Formats.duration(120) == "2h"
    assert Formats.duration(nil) == "—"
  end
end
