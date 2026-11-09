# Apple Controller — Xuper TV Remote for iPhone

Aplicación iOS independiente, escrita en SwiftUI. Controla **Xuper TV Desktop** en Windows por la misma red Wi-Fi.

## Controles

- **Trackpad grande al fondo**: desliza para mover el puntero sobre la TV; toca para hacer clic. Mantén presionado y arrastra para mover carruseles, incluido el de canales en vivo.
- **Volumen**: barra de 0 a 100 para el reproductor.
- **Brillo**: barra de 0 a 100 para ajustar el brillo *del video* en el reproductor. No controla la retroiluminación física de la televisión.
- **Flechas + OK**: navegan y seleccionan.
- **TV / Series / Películas**: accesos rápidos que cambian a esas secciones, incluso desde la reproducción.
- **Volver, Inicio, Pausa, Opciones**: controles de navegación y reproducción.
- **Buscar**: escribe en el iPhone y envía la búsqueda al programa.

## Primer emparejamiento

1. Ejecuta **XuperTVDesktop.exe** de la rama `feature/apple-controller-server` en Windows (no funciona con el EXE viejo).
2. PC e iPhone deben estar conectados a la **misma red Wi-Fi/LAN**. Si Windows pregunta por el firewall, permite la aplicación únicamente en redes privadas.
3. En la parte inferior de Xuper TV verás una dirección, por ejemplo `192.168.1.25:47831`, y un **PIN de seis dígitos**.
4. Abre **Apple Controller**; escribe únicamente `192.168.1.25` en IP y el PIN de la TV.
5. Toca **Conectar al PC**. El iPhone recuerda la autorización en su Keychain; luego se reconectará con la IP que hayas guardado.

Si cambia la IP de Windows, escribe la nueva en la pantalla de conexión y usa el PIN que aparece en el programa. Si el firewall bloquea el puerto TCP **47831**, la app no podrá conectarse.

## Código y compilación

El archivo `project.yml` crea un proyecto Xcode mediante **XcodeGen**. El workflow en `.github/workflows/build-ios.yml` compila para iPhone y adjunta una **IPA sin firma** en Actions → Artifacts. Para instalarla, deberás firmarla con SideStore/AltStore u otra herramienta válida.

El backend de Windows vive en el repositorio separado [Xuper-Tv](https://github.com/adri23rep-stack/Xuper-Tv), rama `feature/apple-controller-server`. La interfaz se basa en la rama Cinematic.

## Conexión y límites

- Solo red local, no nube ni control por internet. Usa HTTP simple sobre LAN privada; **evita Wi-Fi público** y no abras el puerto hacia internet. El código de emparejamiento tiene protección contra intentos repetidos.
- El Windows guarda un token local en `remote_secret.txt`; no se sube a GitHub. El iPhone guarda el token en Keychain.
- Primera versión: emparejamiento por IP + PIN, sin QR y sin descubrimiento automático.
- Las pruebas de GitHub comprueban compilación, no conectividad real ni el comportamiento completo del trackpad. Hay que validar en una PC y un iPhone.

**Sin release; sin merge de esta rama a main antes de validar.**
