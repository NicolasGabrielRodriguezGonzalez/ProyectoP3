defmodule Trivia.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Supervisor de partidas
      Trivia.Supervisor,
      # Servidor de conexión de usuarios
      Trivia.ConnectionServer
    ]

    opts = [strategy: :one_for_one, name: Trivia.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
