defmodule Trivia.ConnectionServer do
  use GenServer

  @users_file "data/users.dat"
  @scores_file "data/scores.dat"

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

  # Obtener top 10 puntajes globales
  def get_top_scores do
    GenServer.call({:global, __MODULE__}, :get_top_scores)
  end

  # Registrar puntajes de una partida
  def register_scores(game_id, tema, scores_map) do
    GenServer.cast({:global, __MODULE__}, {:register_scores, game_id, tema, scores_map})
  end

  ## Callbacks
  def init(_) do
    {:ok, %{connected: %{}, scores: load_scores()}}
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

  # Obtener top 10 desde el estado
  def handle_call(:get_top_scores, _from, state) do
    {:reply, state.scores, state}
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

  # Registrar resultados de una partida y mantener solo el top 10
  def handle_cast({:register_scores, game_id, tema, scores_map}, state) do
    nuevos =
      scores_map
      |> Enum.map(fn {nombre, puntaje} ->
        %{
          nombre: nombre,
          puntaje: puntaje,
          tema: tema,
          game_id: game_id,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      end)

    merged = state.scores ++ nuevos

    top10 =
      merged
      |> Enum.sort_by(& &1.puntaje, :desc)
      |> Enum.take(10)

    persist_scores(top10)

    {:noreply, %{state | scores: top10}}
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

defp load_scores do
  if File.exists?(@scores_file) do
    @scores_file
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn linea ->
      # nombre,puntaje,tema,game_id,timestamp
      [nombre, puntaje, tema, game_id, timestamp] =
        String.split(linea, ",", trim: true)

      %{
        nombre: nombre,
        puntaje: String.to_integer(puntaje),
        tema: tema,
        game_id: game_id,
        timestamp: timestamp
      }
    end)
  else
    []
  end
end

defp persist_scores(scores) do
  contenido =
    scores
    |> Enum.map(fn s ->
      "#{s.nombre},#{s.puntaje},#{s.tema},#{s.game_id},#{s.timestamp}"
    end)
    |> Enum.join("\n")

  File.write!(@scores_file, contenido <> "\n")
end

defp persist_user(%{nombre: nombre, contrasena: contrasena, puntaje: puntaje}) do
  File.write!(@users_file, "#{nombre},#{contrasena},#{puntaje}\n", [:append])
end
end

