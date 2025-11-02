defmodule Trivia.Game do
  alias Trivia.QuestionBank

  # Estructura para almacenar el estado del juego
  defstruct tema: nil, preguntas: [], puntaje: 0, total_preguntas: 0

  @doc """
  Inicia una partida con el tema dado y el número de preguntas.
  """
  def iniciar_partida(tema, cantidad_preguntas) do
    preguntas = QuestionBank.get_random_questions(tema, cantidad_preguntas)

    juego = %Trivia.Game{
      tema: tema,
      preguntas: preguntas,
      total_preguntas: length(preguntas)
    }

    jugar(juego)
  end

  defp jugar(%Trivia.Game{preguntas: []} = juego) do
    IO.puts("\n🎉 ¡Juego terminado!")
    IO.puts("Puntaje final: #{juego.puntaje}")
    juego  # 👈 importante: devolvemos el estado final
  end

  defp jugar(%Trivia.Game{preguntas: [pregunta | resto]} = juego) do
    IO.puts("\n--------------------------------------")
    IO.puts("Tema: #{juego.tema}")
    IO.puts("Pregunta: #{pregunta.texto}")

    Enum.each(pregunta.opciones, fn {letra, texto} ->
      IO.puts("#{letra}) #{texto}")
    end)

    respuesta = IO.gets("Tu respuesta (A/B/C/D): ") |> String.trim() |> String.upcase()
    correcta = Atom.to_string(pregunta.correcta) |> String.upcase()

    puntaje =
      if respuesta == correcta do
        IO.puts("✅ ¡Correcto! +10 puntos")
        juego.puntaje + 10
      else
        IO.puts("❌ Incorrecto. -5 puntos")
        juego.puntaje - 5
      end

    jugar(%Trivia.Game{juego | preguntas: resto, puntaje: puntaje})
  end
end
