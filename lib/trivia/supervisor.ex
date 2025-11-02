defmodule Trivia.Supervisor do
  use Supervisor

  @dynamic_supervisor Trivia.GamesDynamicSupervisor

  ## API

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: @dynamic_supervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Inicia una nueva partida bajo el DynamicSupervisor y la registra globalmente.
  game_opts debe incluir: :game_id, :tema, :preguntas_count, :tiempo_ms, :max_players, :creator
  """
  def start_game(game_opts) when is_map(game_opts) do
    child_spec = %{
      id: {:game, game_opts.game_id},
      start: {Trivia.Game, :start_link, [game_opts]},
      restart: :transient
    }

    {:ok, pid} = DynamicSupervisor.start_child(@dynamic_supervisor, child_spec)

    # Registrar el juego globalmente para que todos los nodos puedan encontrarlo
    :global.register_name({:game, game_opts.game_id}, pid)

    {:ok, pid}
  end

  @doc """
  Devuelve la lista de partidas activas globalmente.
  """
  def list_games do
    :global.registered_names()
    |> Enum.filter(fn
      {:game, _id} -> true
      _ -> false
    end)
    |> Enum.map(fn {:game, id} -> id end)
  end

  @doc """
  Devuelve el PID de un juego dado su game_id.
  Funciona entre nodos usando :global.
  """
  def get_game_pid(game_id) do
    case :global.whereis_name({:game, game_id}) do
      :undefined -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Permite unirse a un juego desde cualquier nodo.
  """
  def join_game(game_id, username, player_pid) do
    case get_game_pid(game_id) do
      {:ok, pid} -> Trivia.Game.join(pid, username, player_pid)
      {:error, :not_found} -> {:error, :game_not_found}
    end
  end
end
