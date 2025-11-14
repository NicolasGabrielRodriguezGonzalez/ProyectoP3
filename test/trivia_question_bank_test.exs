defmodule Trivia.QuestionBankTest do
  use ExUnit.Case, async: true

  alias Trivia.QuestionBank

  test "load_questions carga preguntas desde el archivo" do
    preguntas = QuestionBank.load_questions()

    # Hay preguntas
    assert length(preguntas) > 0

    primera = hd(preguntas)

    # La estructura básica es la esperada
    assert Map.has_key?(primera, :tema)
    assert Map.has_key?(primera, :pregunta)
    assert Map.has_key?(primera, :opciones)
    assert Map.has_key?(primera, :correcta)
  end

  test "get_random_questions filtra por tema y limita la cantidad" do
    tema = "ciencia"
    n = 3

    preguntas = QuestionBank.get_random_questions(tema, n)

    # Devuelve exactamente n preguntas (según el archivo data/questions.dat)
    assert length(preguntas) == n

    # Todas las preguntas son del tema solicitado
    assert Enum.all?(preguntas, fn q -> q.tema == tema end)
  end
end
