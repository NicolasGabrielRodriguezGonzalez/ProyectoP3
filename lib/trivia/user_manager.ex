defmodule Trivia.UserManager do
  @moduledoc """
  Módulo encargado de manejar el registro, login y almacenamiento
  de usuarios en users.dat, además de iniciar partidas de trivia.
  """

  alias Trivia.Game

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
      {:ok, msg} -> IO.puts("✅ #{msg}")
      {:error, msg} -> IO.puts("❌ #{msg}")
    end
  end

  # === LOGIN INTERACTIVO ===
  defp login_interactivo do
    IO.puts("\n--- Inicio de sesión ---")
    nombre = IO.gets("Nombre de usuario: ") |> String.trim()
    contrasena = IO.gets("Contraseña: ") |> String.trim()

    case login(nombre, contrasena) do
      {:ok, usuario} ->
        IO.puts("\n✅ Sesión iniciada correctamente como #{usuario.nombre}")
        menu_usuario(usuario)

      {:error, msg} ->
        IO.puts("❌ #{msg}")
    end
  end

  # === MENÚ DE USUARIO YA LOGEADO ===
  defp menu_usuario(usuario) do
    IO.puts("\n--- Menú de Usuario ---")
    IO.puts("1. Ver puntaje")
    IO.puts("2. Cerrar sesión")
    IO.puts("3. Jugar trivia")

    opcion = IO.gets("Seleccione una opción: ") |> String.trim()

    case opcion do
      "1" ->
        IO.puts("🏆 Tu puntaje actual es: #{usuario.puntaje}")
        menu_usuario(usuario)

      "2" ->
        IO.puts("👋 Sesión cerrada.")

      "3" ->
        tema = IO.gets("\nElige un tema: ") |> String.trim()
        cantidad = IO.gets("¿Cuántas preguntas deseas?: ") |> String.trim() |> String.to_integer()

        # Jugar partida
        juego = Game.iniciar_partida(tema, cantidad)

        # Actualizar puntaje del usuario
        nuevo_puntaje = usuario.puntaje + juego.puntaje
        IO.puts("\n⭐ Tu nuevo puntaje total es: #{nuevo_puntaje}")

        actualizar_puntaje(usuario.nombre, nuevo_puntaje)

        menu_usuario(%{usuario | puntaje: nuevo_puntaje})

      _ ->
        IO.puts("❌ Opción inválida.")
        menu_usuario(usuario)
    end
  end

  # === LÓGICA DE REGISTRO Y LOGIN ===
  def registrar_usuario(nombre, contrasena) do
    usuarios = cargar_usuarios()

    case Enum.find(usuarios, fn u -> u.nombre == nombre end) do
      nil ->
        nuevo_usuario = %Trivia.UserManager{nombre: nombre, contrasena: contrasena, puntaje: 0}
        guardar_usuario(nuevo_usuario)
        {:ok, "Usuario registrado correctamente."}

      _ ->
        {:error, "El usuario ya existe."}
    end
  end

  def login(nombre, contrasena) do
    usuarios = cargar_usuarios()

    case Enum.find(usuarios, fn u -> u.nombre == nombre end) do
      nil -> {:error, "Usuario no encontrado."}
      usuario ->
        if usuario.contrasena == contrasena do
          {:ok, usuario}
        else
          {:error, "Contraseña incorrecta."}
        end
    end
  end

  def cargar_usuarios do
    if File.exists?(@users_file) do
      File.read!(@users_file)
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_usuario/1)
    else
      []
    end
  end

  defp parse_usuario(linea) do
    [nombre, contrasena, puntaje] = String.split(linea, ",")
    %Trivia.UserManager{
      nombre: nombre,
      contrasena: contrasena,
      puntaje: String.to_integer(puntaje)
    }
  end

  defp guardar_usuario(usuario) do
    File.write!(
      @users_file,
      "#{usuario.nombre},#{usuario.contrasena},#{usuario.puntaje}\n",
      [:append]
    )
  end

  # === NUEVO: ACTUALIZAR PUNTAJE EN EL ARCHIVO ===
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
end
