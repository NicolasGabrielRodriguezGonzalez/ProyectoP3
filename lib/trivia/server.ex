defmodule Trivia.ConnectionServer do
  use GenServer

  @users_file "data/users.dat"

  ## API
  def start_link(_opts) do
    # Registramos globalmente para nodos distribuidos
    GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})
  end

  # Conectar un usuario
  def connect(username, password) do
    GenServer.call({:global, __MODULE__}, {:connect, username, password})
  end

  # Desconectar un usuario
  def disconnect(username) do
    GenServer.call({:global, __MODULE__}, {:disconnect, username})
  end

  # Listar juegos activos (delegando al supervisor de juegos)
  def list_games do
    Trivia.Supervisor.list_games()
  end

  # Enviar un mensaje a un usuario específico (incluso remoto)
  def send_user(username, msg) do
    GenServer.cast({:global, __MODULE__}, {:send_user, username, msg})
  end

  # Broadcast a todos los usuarios conectados
  def broadcast(msg) do
    GenServer.cast({:global, __MODULE__}, {:broadcast, msg})
  end

  ## Callbacks
  def init(_) do
    {:ok, %{connected: %{}}}
  end

  # Conexión de usuario
  def handle_call({:connect, username, password}, {pid, _ref}, state) do
    usuarios = load_users()

    case Enum.find(usuarios, fn u -> u.nombre == username end) do
      nil ->
        # Registrar usuario
        usuario = %{nombre: username, contrasena: password, puntaje: 0}
        persist_user(usuario)
        connected = Map.put(state.connected, username, {pid, node()})
        {:reply, {:ok, :registered}, %{state | connected: connected}}

      u ->
        if u.contrasena == password do
          connected = Map.put(state.connected, username, {pid, node()})
          {:reply, {:ok, :connected}, %{state | connected: connected}}
        else
          {:reply, {:error, :invalid_credentials}, state}
        end
    end
  end

  # Desconexión de usuario
  def handle_call({:disconnect, username}, _from, state) do
    connected = Map.delete(state.connected, username)
    {:reply, :ok, %{state | connected: connected}}
  end

  # Enviar mensaje a usuario remoto
  def handle_cast({:send_user, username, msg}, state) do
    case Map.get(state.connected, username) do
      {pid, node} ->
        send({pid, node}, msg)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  # Broadcast a todos los usuarios
  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state.connected, fn {_user, {pid, node}} ->
      send({pid, node}, msg)
    end)

    {:noreply, state}
  end

  # --- Helpers de persistencia ---
  defp load_users do
    if File.exists?(@users_file) do
      File.read!(@users_file)
      |> String.split("\n", trim: true)
      |> Enum.map(fn linea ->
        [nombre, contrasena, puntaje] = String.split(linea, ",", trim: true)
        %{nombre: nombre, contrasena: contrasena, puntaje: String.to_integer(puntaje)}
      end)
    else
      []
    end
  end

  defp persist_user(%{nombre: nombre, contrasena: contrasena, puntaje: puntaje}) do
    File.write!(@users_file, "#{nombre},#{contrasena},#{puntaje}\n", [:append])
  end
end
