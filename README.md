# Hydra iOS Test — catálogo original de XUPER-HYDRA-PORT-WEBOS

Port experimental nativo para iPhone basado en el código del proyecto LG [cristianco7/XUPER-HYDRA-PORT-WEBOS](https://github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS), fijado al commit `d8451ee05b3c1f0581d9d8c4fb77e7fbe7eff06b`.

**Esta rama NO utiliza el catálogo de Nova, Apple Controller ni de Papas_y_Arroz.** No modifica la rama main del control de iOS.

## Qué funciona en esta etapa

- Contiene `webos/fidelity/data/portal.js` del port LG (snapshot del 27 de octubre de 2026) y su interfaz HTML/CSS/JS original.
- El cliente `ios/Sources/HydraPortalClient.swift` habla directamente con el portal que define el código LG, sin PC y sin Node.
- El puente `ios/Sources/HydraRootView.swift` conecta los métodos de catálogo (`home`, `search`, `detail`, `liveCategories`, `liveChannels`) con Swift.
- El catálogo original se ve de inmediato; luego la app intenta refrescarlo desde el portal. Puede mostrar errores si el servidor rechaza la sesión de iPhone.
- Se limita a sesiones nuevas obtenidas del portal. No reutiliza sesiones ajenas ni las semillas compartidas del repositorio LG.

## Limitaciones IMPORTANTES

- El servidor puede rechazar la activación o no responder. En ese caso solo se ve el catálogo guardado del código LG.
- La reproducción completa aún **no** funciona: el sistema original usa proxy, autorizaciones de medios, FFmpeg y otros componentes Node del televisor. No se han portado ni se intentan esquivar DRM o permisos del servicio.
- La interfaz es la original para televisión horizontal, todavía sin optimizar para controles táctiles.
- No se ha probado en un iPhone real. Compilación Xcode exitosa no equivale a catálogo remoto confirmado.

## IPA

Compilar en GitHub → Actions → **Hydra iOS - IPA sin firmar** sobre esta rama. Descarga el artifact `HydraIOS-test-unsigned` y firma el archivo .ipa con SideStore/AltStore. No se publica en App Store.

## Créditos y licencias

El código original del port se publica con licencia MIT; logos, imágenes y material de terceros tienen derechos separados. Ver [LICENSE](https://github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS/blob/main/LICENSE) y [THIRD_PARTY.md](https://github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS/blob/main/THIRD_PARTY.md) del proyecto fuente.
