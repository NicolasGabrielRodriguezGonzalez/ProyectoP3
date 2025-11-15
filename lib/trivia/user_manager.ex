defmodule Trivia.UserManager do
  @moduledoc """
  Maneja registro, login y almacenamiento de usuarios.
  Ahora integrado con ConnectionServer para nodos distribuidos.
  """

  alias Trivia.{Supervisor, Game, ConnectionServer}

  @users_file "data/users.dat"
  defstruct nombre: "", contrasena: "", puntaje: 0

  # === PUNTO DE ENTRADA PRINCIPAL ===
  def iniciar_sistema do
    IO.puts("\n--- Gestión de Usuarios ---")
    IO.puts("1. Registrarse")
    IO.puts("2. Iniciar sesión")
    IO.puts("3. Salir")

    opcion = IO.gets("Seleccione una opción: ") |> String.trim()

    case opcion do
      "1" ->
        registrar_interactivo()
        iniciar_sistema()

      "2" ->
        login_interactivo()
        iniciar_sistema()

      "3" ->
        IO.puts("👋 Saliendo del sistema de usuarios...")

      _ ->
        IO.puts("❌ Opción inválida, inténtelo de nuevo.")
        iniciar_sistema()
    end
  end

  # === REGISTRO INTERACTIVO ===
  defp registrar_interactivo do
    IO.puts("\n--- Registro de nuevo usuario ---")
    nombre = IO.gets("Nombre de usuario: ") |> String.trim()
    contrasena = IO.gets("Contraseña: ") |> String.trim()

    case registrar_usuario(nombre, contrasena) do
      {:ok, msg} ->
        IO.puts("✅ #{msg}")

      {:error, msg} ->
        IO.puts("❌ #{msg}")
    end
  end

  # === LOGIN INTERACTIVO ===
  defp login_interactivo do
    IO.puts("\n--- Inicio de sesión ---")
    nombre = IO.gets("Nombre de usuario: ") |> String.trim()
    contrasena = IO.gets("Contraseña: ") |> String.trim()

    # Conectamos usando ConnectionServer global
    case ConnectionServer.connect(nombre, contrasena) do
      {:ok, :registered} ->
        IO.puts("✅ Usuario registrado y conectado como #{nombre}")
        menu_usuario(%{nombre: nombre, puntaje: 0})

      {:ok, :connected} ->
        IO.puts("✅ Sesión iniciada correctamente como #{nombre}")
        # cargar puntaje localmente
        usuario = cargar_usuarios() |> Enum.find(fn u -> u.nombre == nombre end)
        menu_usuario(usuario)

      {:error, :invalid_credentials} ->
        IO.puts("❌ Contraseña incorrecta.")
    end
  end

  # === MENÚ DE USUARIO YA LOGEADO ===
  defp menu_usuario(usuario) do
    IO.puts("\n--- Menú de Usuario ---")
    IO.puts("1. Ver puntaje")
    IO.puts("2. Cerrar sesión")
    IO.puts("3. Crear partida trivia")
    IO.puts("4. Listar partidas activas")
    IO.puts("5. Unirse a una partida activa")
    IO.puts("6. Ver mejores puntajes (Top 10)")

    opcion = IO.gets("Seleccione una opción: ") |> String.trim()

    case opcion do
      "1" ->
        IO.puts("🏆 Tu puntaje actual es: #{usuario.puntaje}")
        menu_usuario(usuario)

      "2" ->
        ConnectionServer.disconnect(usuario.nombre)
        IO.puts("👋 Sesión cerrada.")

      "3" ->
        tema = IO.gets("\nElige un tema: ") |> String.trim()

        cantidad =
          IO.gets("¿Cuántas preguntas deseas?: ")
          |> String.trim()
          |> String.to_integer()

        game_id = "game_" <> Integer.to_string(:erlang.unique_integer([:positive]))

        {:ok, _pid} =
          Supervisor.start_game(%{
            game_id: game_id,
            tema: tema,
            preguntas_count: cantidad,
            tiempo_ms: 15_000,
            max_players: 4,
            creator: usuario.nombre
          })

        {:ok, _state} = Game.join(game_id, usuario.nombre, self())

        IO.puts("\n🎮 Partida #{game_id} creada en tema '#{tema}' con #{cantidad} preguntas.")
        IO.puts("🕓 Esperando que otros jugadores se unan...")
        IO.puts("Cuando todos estén listos, escribe 'comenzar' para iniciar la partida.")

        esperar_inicio(usuario, game_id)

      "4" ->
        activos = Supervisor.list_games()
        IO.puts("\n📜 Partidas activas:")

        Enum.each(activos, fn g ->
          IO.puts("- #{g}")
        end)

        menu_usuario(usuario)

      "5" ->
        activos = Supervisor.list_games()

        if Enum.empty?(activos) do
          IO.puts("❌ No hay partidas activas en este momento.")
          menu_usuario(usuario)
        else
          IO.puts("\n🔹 Partidas disponibles:")

          Enum.each(activos, fn g ->
            IO.puts("- #{g}")
          end)

          game_id =
            IO.gets("👉 Escriba el ID de la partida a la que desea unirse: ")
            |> String.trim()

          case Game.join(game_id, usuario.nombre, self()) do
            {:ok, _state} ->
              IO.puts("✅ Te has unido a la partida #{game_id}. Esperando preguntas...")
              esperar_eventos(usuario, game_id)

            {:error, :full} ->
              IO.puts("❌ La partida está llena. Intente con otra.")
              menu_usuario(usuario)

            {:error, :not_accepting} ->
              IO.puts("⚠️ La partida ya está en curso o finalizada.")
              menu_usuario(usuario)

            {:error, :game_not_found} ->
              IO.puts("🚫 No se encontró la partida indicada.")
              menu_usuario(usuario)
          end
        end

      "6" ->
        mostrar_top_scores()
        menu_usuario(usuario)

      _ ->
        IO.puts("❌ Opción inválida.")
        menu_usuario(usuario)
    end
  end

  # === TOP 10 PUNTAJES GLOBALES ===
  defp mostrar_top_scores do
    top = ConnectionServer.get_top_scores()

    if Enum.empty?(top) do
      IO.puts("\n📊 Aún no hay puntajes registrados.")
    else
      IO.puts("\n🏆 Top 10 mejores puntajes globales:")

      top
      |> Enum.with_index(1)
      |> Enum.each(fn {entry, idx} ->
        IO.puts(
          "#{idx}. #{entry.nombre} - #{entry.puntaje} pts " <>
            "(tema: #{entry.tema}, partida: #{entry.game_id})"
        )
      end)
    end
  end

  defp esperar_inicio(usuario, game_id) do
    entrada =
      IO.gets("👉 Escribe 'comenzar' para iniciar o 'salir' para cancelar: ")
      |> String.trim()

    case entrada do
      "comenzar" ->
        case Game.start_game(game_id, usuario.nombre) do
          {:ok, :started} ->
            IO.puts("🚀 ¡Partida iniciada!")
            esperar_eventos(usuario, game_id)

          {:error, :no_questions} ->
            IO.puts("⚠️ No hay suficientes preguntas para ese tema.")

          {:error, :not_creator} ->
            IO.puts("❌ Solo el creador puede iniciar la partida.")
        end

      "salir" ->
        IO.puts("❌ Partida cancelada.")
        :ok

      _ ->
        IO.puts("⚠️ Opción inválida.")
        esperar_inicio(usuario, game_id)
    end
  end

  # === LÓGICA REGISTRO/LOGIN local ===
  def registrar_usuario(nombre, contrasena) do
    usuarios = cargar_usuarios()

    case Enum.find(usuarios, fn u -> u.nombre == nombre end) do
      nil ->
        nuevo_usuario = %Trivia.UserManager{
          nombre: nombre,
          contrasena: contrasena,
          puntaje: 0
        }

        guardar_usuario(nuevo_usuario)
        {:ok, "Usuario registrado correctamente."}

      _ ->
        {:error, "El usuario ya existe."}
    end
  end

  def cargar_usuarios do
    if File.exists?(@users_file) do
      File.read!(@users_file)
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_usuario/1)
    else
      []
    end
  end

  defp parse_usuario(linea) do
    [nombre, contrasena, puntaje] =
      linea
      |> String.replace("\r", "")
      |> String.split(",")

    %Trivia.UserManager{
      nombre: String.trim(nombre),
      contrasena: String.trim(contrasena),
      puntaje:
        puntaje
        |> String.trim()
        |> String.replace("\r", "")
        |> String.to_integer()
    }
  end

  defp guardar_usuario(usuario) do
    File.write!(
      @users_file,
      "#{usuario.nombre},#{usuario.contrasena},#{usuario.puntaje}\n",
      [:append]
    )
  end

  def actualizar_puntaje(nombre, nuevo_puntaje) do
    usuarios_actualizados =
      cargar_usuarios()
      |> Enum.map(fn
        %Trivia.UserManager{nombre: ^nombre} = u -> %{u | puntaje: nuevo_puntaje}
        u -> u
      end)

    contenido =
      usuarios_actualizados
      |> Enum.map(fn u -> "#{u.nombre},#{u.contrasena},#{u.puntaje}" end)
      |> Enum.join("\n")

    File.write!(@users_file, contenido <> "\n")
  end

  # Escucha eventos enviados por el servidor del juego
  defp esperar_eventos(usuario, game_id) do
    receive do
      {:question, index, pregunta} ->
        IO.puts("\n🧠 Pregunta ##{index + 1}: #{pregunta.pregunta}")

        IO.puts("A) #{pregunta.opciones[:A] || pregunta.opciones[:a]}")
        IO.puts("B) #{pregunta.opciones[:B] || pregunta.opciones[:b]}")
        IO.puts("C) #{pregunta.opciones[:C] || pregunta.opciones[:c]}")
        IO.puts("D) #{pregunta.opciones[:D] || pregunta.opciones[:d]}")

        # Leer la respuesta en OTRO proceso, para no bloquear el receive principal
        spawn(fn ->
          respuesta =
            IO.gets("👉 Tu respuesta (A/B/C/D): ")
            |> to_string()
            |> String.trim()
            |> String.upcase()

          Trivia.Game.answer(game_id, usuario.nombre, respuesta)
        end)

        esperar_eventos(usuario, game_id)

      {:question_timeout, idx, correcta} ->
        IO.puts("⏰ Tiempo agotado para la pregunta #{idx + 1}. Respuesta correcta: #{correcta}")
        esperar_eventos(usuario, game_id)

      {:game_finished, scores} ->
        IO.puts("\n🏁 ¡La partida ha terminado! Resultados finales:")

        Enum.each(scores, fn {user, score} ->
          IO.puts("• #{user}: #{score} pts")
        end)

        IO.puts("\nVolviendo al menú principal...")
        menu_usuario(usuario)

      {:player_joined, username} ->
        IO.puts("👥 #{username} se ha unido a la partida.")
        esperar_eventos(usuario, game_id)

      {:player_left, username} ->
        IO.puts("👋 #{username} ha salido de la partida.")
        esperar_eventos(usuario, game_id)

      _ ->
        esperar_eventos(usuario, game_id)
    end
  end
end
