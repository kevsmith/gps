defmodule GpsTest do
  use ExUnit.Case
  doctest Gps

  def setup_all do
    {:ok, _pid} = Gps.Monitor.start_link()
    :ok
  end

  test "Parsed current GPS position" do
    {:ok, position} = Gps.current_position()
    assert position.lat == 35.86916
    assert position.long == -78.67512
  end
end
