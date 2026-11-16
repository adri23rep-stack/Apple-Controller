# Reproductor privado independiente de Windows

La pantalla **Acceso privado** ahora usa una biblioteca de iOS guardada en el teléfono.
La app no llama a /mobile/catalog ni a los endpoints del control durante la
reproducción privada. El control remoto de Windows sigue funcionando como antes.

## Qué funciona sin PC
- PIN propio de 6–12 cifras guardado en iOS Keychain.
- Importar listas M3U de Archivos (texto UTF-8, hasta 4 MB).
- Abrir listas M3U por URL HTTPS; actualizar fuentes por Internet.
- Agregar URL HTTPS directa a video MP4 o HLS (.m3u8).
- Biblioteca persistente, búsqueda, categorías, portadas declaradas en el M3U.
- Reproducción local nativa con AVPlayer, sin abrir nada en la TV.

## Qué NO está incluido
- El catálogo oficial/automático del servicio Xuper TV aún **no** se conecta
  desde iOS. En Windows depende de activación de una sesión, llamadas cifradas
  a la API y, para muchos canales, autorización específica de contenidos.
- No hay un paquete de canales preinstalado ni fuentes inventadas.
- Streaming que exija DRM, headers de sesión privados o protocolos incompatibles
  no será reproducible solo por guardar su URL.
- Una página HTML, enlace de catálogo /player/ o un 404 no es un video directo.

## Instalación
Compilar la rama `feature/remote-no-scroll-layout` de Apple-Controller;
no cambiar bundle ID ni borrar la aplicación si se desea conservar el PIN.
Se puede abrir la pantalla oculta desde el encabezado del control **sin tener
Windows encendido o emparejado**.

La rama main de ambos repos queda intacta. No se publica release.
