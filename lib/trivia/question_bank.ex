defmodule Trivia.QuestionBank do
  @moduledoc """
  Módulo encargado de cargar, filtrar y entregar preguntas desde el archivo questions.dat.
  Formato esperado (CSV simple):
  tema,pregunta,A,B,C,D,respuesta_correcta
  """

  @questions_file "data/questions.dat"

  # Carga todas las preguntas desde el archivo
  def load_questions do
    @questions_file
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_line/1)
  end

  # Parsea una línea CSV en un mapa
  defp parse_line(linea) do
  [tema, pregunta, a, b, c, d, correcta] =
    String.split(linea, ",")
    |> Enum.map(&String.trim/1)

  %{
    tema: tema,
    pregunta: pregunta,  # 👈 antes decía :texto
    opciones: %{A: a, B: b, C: c, D: d},
    correcta: String.to_atom(String.trim(correcta))
  }
end
  # Devuelve n preguntas aleatorias filtradas por tema
  def get_random_questions(tema, n) do
    load_questions()
    |> Enum.filter(fn q -> q.tema == tema end)
    |> Enum.shuffle()
    |> Enum.take(n)
  end
end
