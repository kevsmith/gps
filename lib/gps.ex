defmodule Gps do
  @moduledoc """
  Documentation for Gps.
  """
  def current_position() do
    Gps.Monitor.current_position()
  end
end
