# Hydra LG iOS — prueba de catálogo independiente

Rama experimental del repositorio Apple-Controller. **NO modifica main** ni utiliza el catálogo de Nova/Papas_y_Arroz ni sus servicios de PC.

Se usa exclusivamente el código fuente del port LG [cristianco7/XUPER-HYDRA-PORT-WEBOS](https://github.com/cristianco7/XUPER-HYDRA-PORT-WEBOS), fijado al commit `d8451ee05b3c1f0581d9d8c4fb77e7fbe7eff06b`.

## Qué se está probando

**La hipótesis:** ¿puede el iPhone consultar por sí solo el catálogo utilizado por el port LG, para saber si más adelante serviría como fuente de emergencia en Nova?

- En cada build, `scripts/prepare-resources.py` descarga la fuente original LG y extrae `data/portal.js` a `hydra-catalog.json`. Se comprueba que contenga **610 títulos** del **27 de octubre de 2026**.
- Al abrir, la app usa una **interfaz nativa de SwiftUI** para no arrancar automáticamente el código de televisión LG, que provocaba problemas en iPhone.
- Muestra al instante el catálogo original guardado, con búsqueda, categorías y detalles, sin conexión a la PC.
- El botón **Probar catálogo EN VIVO** solicita una nueva sesión directamente al portal que define el port LG. Si acepta, consulta películas y series, muestra los resultados y permite comparar guardado vs. en vivo.
- Si la sesión o la descarga falla, no bloquea el catálogo guardado y muestra el error sin publicar credenciales ni tokens.

## Límites de la prueba

- La compilación Xcode no garantiza que el instalador de terceros o el iPhone no cierren la app. Es una prueba experimental; falta confirmación en iPhone real.
- **Ver títulos guardados no demuestra conexión remota.** Solo un mensaje de catálogo EN VIVO recibido con resultados demuestra que la consulta funcionó en esa prueba.
- La **reproducción no está integrada**: el port LG utiliza un servicio Node de webOS para resolver medios. No se elude ningún DRM, autenticación ni control de acceso.
- No se copian sesiones, tokens ni configuraciones privadas de otras instalaciones; el servidor puede rechazar nuevas sesiones.
- Se conserva el código original LG como referencia en el paquete, pero el navegador visual inicial ahora es SwiftUI para aislar las causas del crash.

## Compilación

GitHub → Actions → **Hydra LG iOS - IPA independiente** → artifact `HydraIOS-LG-Catalogo-Standalone`. La IPA sale **sin firma**, debes firmarla para instalarla con SideStore/AltStore.

El workflow también intenta abrir una compilación de simulador. Un fallo del simulador de Actions se registra como diagnóstico separado y no bloquea la IPA para iPhone. No sustituye las pruebas en un dispositivo real.

Código original MIT; imágenes, marcas y contenido son de sus titulares y pueden tener licencias diferentes. Consultar la licencia del repositorio fuente.
