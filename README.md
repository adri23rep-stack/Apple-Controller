# Hydra iOS Test (rama experimental)

Port del cliente webOS [XUPER-HYDRA-PORT-WEBOS](https://github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS) para iPhone. **No modifica main ni el control de iOS**: esta rama contiene un proyecto Xcode independiente.

## Qué se compila
En GitHub Actions se descargan los recursos HTML/CSS/JS de Hydra fijados al commit `d8451ee05b3c1f0581d9d8c4fb77e7fbe7eff06b`, incluida la copia del catálogo, y se aplica el parche mínimo para mostrar la interfaz original en WKWebView.
El port incluye modo offline (catálogo histórico) y LAN (intenta catálogo en vivo desde un servicio Node instalado en la PC). **No incluye Node ni FFmpeg dentro del iPhone.**

## IPA
Actions → **Hydra iOS - IPA sin firmar** → último run de esta rama → descargar **HydraIOS-test-unsigned**. Hay que firmarla con SideStore/AltStore para instalar.

## Catálogo en vivo
Para probarlo usa el servicio incluido en el paquete de fuentes `Hydra-iOS-Test-Fuentes.zip` de la conversación, dentro de `desktop-service/`. Ejecuta `INICIAR-TEST-IPHONE.ps1` con tu IP LAN privada y configura esa dirección en la app. Conecta PC + iPhone a la misma Wi-Fi. No abras los puertos a internet.
Sin servicio Node, la app muestra solo la copia antigua del catálogo: búsquedas y reproducción no están garantizadas.

## Fuentes y límites
El proyecto original usa código MIT (© 2026 cristianco7); los recursos del APK, logos y materiales audiovisuales no están cubiertos por esa licencia. El enlace al port original está fijado para reproducibilidad. Esta rama no contiene claves ni tokens privados.
No se eluden DRM ni controles de acceso. No probado todavía en iPhone real.
