defmodule Trivia.GameTest do
  use ExUnit.Case

  alias Trivia.Game

  # Creamos una partida "limpia" para cada test
  setup do
    game_id = "test-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    opts = %{
      game_id: game_id,
      tema: "ciencia",
      creator: "alice",
      max_players: 2,
      preguntas_count: 2,
      tiempo_ms: 50
    }

    {:ok, pid} = Game.start_link(opts)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    %{game_id: game_id, pid: pid, creator: "alice"}
  end

  test "info devuelve un resumen inicial correcto", %{game_id: game_id} do
    info = Game.info(game_id)

    assert info.game_id == game_id
    assert info.tema == "ciencia"
    assert info.status == :waiting
    assert info.players == []
    assert info.current_index == 0
    # scores es un mapa vacío al inicio
    assert info.scores == %{}
  end

  test "join permite unirse mientras haya espacio y falla al llenarse", %{game_id: game_id} do
    # Usamos self() como pid ficticio del jugador
    assert {:ok, _state} = Game.join(game_id, "alice", self())
    assert {:ok, _state} = Game.join(game_id, "bob", self())
    assert {:error, :full} = Game.join(game_id, "charlie", self())
  end

  test "start_game solo puede ejecutarlo el creador", %{game_id: game_id, creator: creator} do
    # Un usuario que no es el creador no puede iniciar la partida
    assert {:error, :not_creator} = Game.start_game(game_id, "otro_usuario")

    # El creador sí puede iniciar la partida
    assert {:ok, :started} = Game.start_game(game_id, creator)
  end

  test "start_game cambia el estado de la partida a :running", %{game_id: game_id, creator: creator} do
    assert {:ok, :started} = Game.start_game(game_id, creator)

    # Después de iniciar, el info debe reflejar el nuevo estado
    info = Game.info(game_id)
    assert info.status == :running
    # Ya debe haber un índice de pregunta actual
    assert is_integer(info.current_index)
  end
end
