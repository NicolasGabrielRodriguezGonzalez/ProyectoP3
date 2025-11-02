defmodule Trivia.Game do
  use GenServer
  alias Trivia.QuestionBank

  @moduledoc """
  GenServer de una partida de trivia distribuida.
  """

  defstruct [
    :game_id,
    :tema,
    preguntas: [],
    tiempo_ms: 15_000,
    max_players: 4,
    players: %{},        # %{username => {pid, node}}
    scores: %{},         # %{username => integer}
    status: :waiting,    # :waiting | :running | :finished
    current_index: 0,
    timer_ref: nil,
    creator: nil
  ]

  # ----------------------
  # API Distribuida
  # ----------------------

  # Nombre global del GenServer
  def via(game_id), do: {:global, {:game, game_id}}

  # Iniciar partida
  def start_link(%{game_id: game_id} = opts) do
    GenServer.start_link(__MODULE__, opts, name: via(game_id))
  end

  # Unirse a la partida
  def join(game_id, username, player_pid) do
    GenServer.call(via(game_id), {:join, username, player_pid, Node.self()})
  end

  # Salir de la partida
  def leave(game_id, username) do
    GenServer.cast(via(game_id), {:leave, username})
  end

  # Iniciar la partida (solo creador)
  def start_game(game_id, starter_username) do
    GenServer.call(via(game_id), {:start_game, starter_username})
  end

  # Información de la partida
  def info(game_id) do
    GenServer.call(via(game_id), :info)
  end

  # Enviar respuesta
  def answer(game_id, username, respuesta) do
    GenServer.cast(via(game_id), {:answer, username, respuesta})
  end

  # ----------------------
  # Callbacks
  # ----------------------

  def init(opts) do
    state = %__MODULE__{
      game_id: opts.game_id,
      tema: opts.tema || "general",
      tiempo_ms: opts.tiempo_ms || 15_000,
      max_players: opts.max_players || 4,
      creator: opts.creator
    }

    {:ok, state}
  end

  # Join
  def handle_call({:join, username, pid, node}, _from, %__MODULE__{status: :waiting} = s) do
    if map_size(s.players) >= s.max_players do
      {:reply, {:error, :full}, s}
    else
      players = Map.put(s.players, username, {pid, node})
      scores = Map.put_new(s.scores, username, 0)
      new_state = %{s | players: players, scores: scores}

      broadcast(new_state, {:player_joined, username})
      {:reply, {:ok, new_state}, new_state}
    end
  end

  def handle_call({:join, _username, _pid, _node}, _from, s) do
    {:reply, {:error, :not_accepting}, s}
  end

  # Start game
  def handle_call({:start_game, starter}, _from, %__MODULE__{creator: starter} = s) do
    preguntas = QuestionBank.get_random_questions(s.tema, 10)
    new_state = %{s | preguntas: preguntas, status: :running, current_index: 0}

    broadcast(new_state, {:game_started, s.game_id})
    send_question(new_state)

    {:reply, {:ok, :started}, new_state}
  end

  def handle_call({:start_game, _starter}, _from, s) do
    {:reply, {:error, :not_creator}, s}
  end

  # Info
  def handle_call(:info, _from, s) do
    summary = %{
      game_id: s.game_id,
      tema: s.tema,
      status: s.status,
      players: Map.keys(s.players),
      scores: s.scores,
      current_index: s.current_index
    }

    {:reply, summary, s}
  end

  # Leave
  def handle_cast({:leave, username}, s) do
    players = Map.delete(s.players, username)
    scores = Map.delete(s.scores, username)
    new_state = %{s | players: players, scores: scores}

    broadcast(new_state, {:player_left, username})
    {:noreply, new_state}
  end

  # Answer
  def handle_cast({:answer, username, respuesta}, %__MODULE__{status: :running} = s) do
    idx = s.current_index
    pregunta = Enum.at(s.preguntas, idx)

    if pregunta == nil do
      {:noreply, s}
    else
      correcta = pregunta.correcta |> to_string() |> String.upcase()
      resp_up = String.trim(to_string(respuesta)) |> String.upcase()

      scores =
        if resp_up == correcta do
          Map.update!(s.scores, username, &(&1 + 10))
        else
          Map.update!(s.scores, username, &(&1 - 5))
        end

      new_state = %{s | scores: scores}
      {:noreply, new_state}
    end
  end

  # Question timeout
  def handle_info({:question_timeout, index}, %__MODULE__{current_index: index} = s) do
    pregunta = Enum.at(s.preguntas, index)
    broadcast(s, {:question_timeout, index, pregunta.correcta})

    next_index = index + 1

    if next_index >= length(s.preguntas) do
      broadcast(s, {:game_finished, s.scores})
      final_state = %{s | status: :finished, timer_ref: nil}
      {:noreply, final_state}
    else
      new_state = %{s | current_index: next_index}
      send_question(new_state)
      {:noreply, new_state}
    end
  end

  def handle_info(_info, s), do: {:noreply, s}

  # ----------------------
  # Helpers
  # ----------------------

  # Broadcast a todos los jugadores (incluso remotos)
defp broadcast(%__MODULE__{players: players}, msg) do
  Enum.each(players, fn {_user, {pid, node}} ->
    if Node.ping(node) == :pong do
      # enviar el mensaje al PID remoto usando :rpc.cast
      :rpc.cast(node, Kernel, :send, [pid, msg])
    end
  end)
end


  # Enviar pregunta actual
  defp send_question(%__MODULE__{current_index: idx, preguntas: preguntas, tiempo_ms: tiempo} = s) do
    pregunta = Enum.at(preguntas, idx)
    broadcast(s, {:question, idx, pregunta})
    Process.send_after(self(), {:question_timeout, idx}, tiempo)
  end
end
