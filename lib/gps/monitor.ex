require Logger

defmodule Gps.Position do
  defstruct [:lat, :long]

  def parse(lat, lat_dir, long, long_dir) do
    case {float_to_degrees(lat, 2), float_to_degrees(long, 3)} do
      {{:error, :bad_data}, _} ->
        {:error, :bad_data}

      {_, {:error, :bad_data}} ->
        {:error, :bad_data}

      {lat, long} ->
        {:ok, %__MODULE__{lat: ensure_sign(lat, lat_dir), long: ensure_sign(long, long_dir)}}
    end
  end

  def update(prior, current) do
    %__MODULE__{
      lat: Float.round(prior.lat * 0.5 + current.lat * 0.5, 9),
      long: Float.round(prior.long * 0.5 + current.long * 0.5, 9)
    }
  end

  def lat(%__MODULE__{lat: lat}), do: Float.round(lat, 6)
  def long(%__MODULE__{long: long}), do: Float.round(long, 6)

  defp float_to_degrees(coord, places) do
    if String.length(coord) < places + 1 do
      {:error, :bad_data}
    else
      {degrees, minutes} = String.split_at(coord, places)
      [minutes, seconds] = String.split(minutes, ".")
      {b, a} = String.split_at(seconds, 2)
      seconds = "#{b}.#{a}"

      Float.round(
        String.to_integer(degrees) + String.to_float("#{minutes}.0") / 60 +
          String.to_float("#{seconds}") / 3600,
        9
      )
    end
  end

  defp ensure_sign(num, "N"), do: num
  defp ensure_sign(num, "S"), do: num * -1
  defp ensure_sign(num, "E"), do: num
  defp ensure_sign(num, "W"), do: num * -1
end

defimpl String.Chars, for: Gps.Position do
  def to_string(%Gps.Position{} = position) do
    "(lat: #{Gps.Position.lat(position)}, long: #{Gps.Position.long(position)})"
  end
end

defmodule Gps.Monitor do
  defstruct gps: nil, timer: nil, position: nil

  use GenServer

  def start_link([]) do
    device = Application.get_env(:gps, :device, "/dev/gps0")
    interval = Application.get_env(:gps, :interval, 5000)

    interval =
      if interval < 5000 and Mix.env() != :test do
        Logger.warn("Configured GPS refresh interval #{interval}ms overridden to 5000ms.")

        5000
      else
        interval
      end

    Logger.debug(
      "Starting Gps.Monitor using device #{device} with refresh interval #{interval}ms"
    )

    GenServer.start_link(__MODULE__, [device, interval], name: __MODULE__)
  end

  def current_position(), do: GenServer.call(__MODULE__, :position)

  def init([device_name, interval]) do
    case File.open(device_name, [:raw, :binary]) do
      {:ok, f} ->
        state = update_gps(%__MODULE__{gps: f})
        Logger.info("Successfully retrieved initial GPS location: #{state.position}")
        {:ok, tref} = :timer.send_interval(interval, :update_gps)
        {:ok, %{state | timer: tref}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_call(:position, _from, state) do
    {:reply, {:ok, state.position}, state}
  end

  def handle_info(:update_gps, state) do
    Logger.debug("Refreshing GPS location")
    state = update_gps(state)
    Logger.debug("GPS location: #{state.position}")
    {:noreply, state}
  end

  defp update_gps(state) do
    case read_gps(state.gps) do
      [] ->
        Logger.debug("No GPS info available")
        state

      ["$GPGLL" | position_data] ->
        Logger.debug("GPS location record received. Updating GPS location")
        update_position(state, position_data)

      data when is_list(data) ->
        update_gps(state)

      error ->
        Logger.warn("Error fetching GPS coordinates: #{inspect(error)}")
        Logger.debug("Using old GPS data")
        state
    end
  end

  defp read_gps(fd) do
    case :file.read_line(fd) do
      {:ok, "\n"} ->
        read_gps(fd)

      {:ok, data} ->
        data
        |> String.trim()
        |> String.split(",")

      :eof ->
        []

      error ->
        error
    end
  end

  defp update_position(%__MODULE__{position: nil} = state, [
         latitude,
         latitude_direction,
         longitude,
         longitude_direction,
         _fix_time,
         "A",
         _checksum
       ]) do
    case Gps.Position.parse(latitude, latitude_direction, longitude, longitude_direction) do
      {:ok, position} ->
        %{state | position: position}

      error ->
        Logger.warn("Error parsing GPS location update: #{inspect(error)}")
        state
    end
  end

  defp update_position(%__MODULE__{position: prior} = state, [
         latitude,
         latitude_direction,
         longitude,
         longitude_direction,
         _fix_time,
         "A",
         _checksum
       ]) do
    case Gps.Position.parse(latitude, latitude_direction, longitude, longitude_direction) do
      {:ok, current} ->
        %{state | position: Gps.Position.update(prior, current)}

      error ->
        Logger.warn("Error parsing GPS location update: #{inspect(error)}")
        state
    end
  end
end
