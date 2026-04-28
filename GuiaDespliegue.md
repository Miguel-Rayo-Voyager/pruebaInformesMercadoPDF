# Guía de Despliegue: Azure Container Apps con Docker

**Proyecto:** InformePDF — Dashboard de Análisis de Mercado Educativo
**Framework:** Shiny for Python
**Plataforma:** Azure Container Apps (Azure for Students)
**Método:** Docker + Azure Container Registry + GitHub Actions
**Región:** Canada Central (política UNIMINUTO)
**Estado actual:** Desplegado y funcionando ✅

---

## Estado de los recursos (confirmados)

| Recurso | Nombre | Estado |
|---|---|---|
| Resource Group | `rg-informes-mercado` | ✅ Creado — Canada Central |
| Container Registry | `informesmercadoacr` | ✅ Creado — Basic SKU, Admin user habilitado |
| Container Apps Environment | `informes-env` | ✅ Creado — Canada Central, plan Consumption |
| Container App | `informes-mercado-app` | ✅ Desplegado — puerto 7860, ingress externo |
| URL pública | `https://informes-mercado-app.braveglacier-8d88d68b.canadacentral.azurecontainerapps.io/` | ✅ Activa |

### Secretos en GitHub (`miguxldsymbiotic/PruebaInformesMERCADO`)

| Secreto | Descripción |
|---|---|
| `AZURE_CLIENT_ID` | ID del Service Principal creado para GitHub Actions |
| `AZURE_CLIENT_SECRET` | Contraseña del Service Principal |
| `AZURE_SUBSCRIPTION_ID` | ID de la suscripción Azure for Students |
| `AZURE_TENANT_ID` | ID del tenant de Azure AD (UNIMINUTO) |
| `ACR_USERNAME` | Usuario Admin del Container Registry |
| `ACR_PASSWORD` | Contraseña Admin del Container Registry |

---

## ¿Por qué Container Apps y no App Service?

| Característica | App Service F1 | Container Apps |
|---|---|---|
| WeasyPrint | ❌ No funciona | ✅ Funciona |
| Playwright + Chromium | ❌ No funciona | ✅ Funciona |
| Control del sistema operativo | ❌ Limitado | ✅ Total (Docker) |
| Costo en Azure for Students | $0 fijo (pero sin PDF) | ~$0 con `min-replicas 0` |
| Complejidad de configuración | Baja | Media |

La clave del costo cero es `--min-replicas 0`: el contenedor **se apaga solo** cuando no hay
visitas y **no consume créditos** en reposo. El único costo fijo es el Container Registry
Basic (~$5 USD/mes del crédito de $100).

---

## Arquitectura del despliegue

```
Tu PC (código)
     │
     │ git push → main
     ▼
GitHub (miguxldsymbiotic/PruebaInformesMERCADO)
     │
     │ .github/workflows/deploy-container-apps.yml se activa
     ▼
GitHub Actions (ubuntu-latest)
     │  1. Login a Azure con Service Principal
     │  2. Login al ACR con Admin credentials
     │  3. docker build + docker push → ACR
     │  4. azure/container-apps-deploy-action actualiza la app
     ▼
Azure Container Registry (informesmercadoacr.azurecr.io)
     │  Almacena la imagen Docker tagueada con el SHA del commit
     ▼
Azure Container Apps (informes-mercado-app)
     │  Corre el contenedor con Shiny en el puerto 7860
     ▼
URL pública → https://informes-mercado-app.braveglacier-8d88d68b.canadacentral.azurecontainerapps.io/
```

---

## Estructura del proyecto

```
PruebaInformesMERCADO/
│
├── Dockerfile                              ← Imagen de producción (ver abajo)
├── .dockerignore                           ← Excluye archivos de desarrollo
├── docker-compose.yml                      ← Solo para pruebas locales
├── requirements.txt                        ← Dependencias Python (raíz del proyecto)
├── requirements_deploy.txt                 ← Copia idéntica (legado, no usada en Docker)
│
├── .github/
│   └── workflows/
│       ├── deploy-container-apps.yml       ← Workflow activo de CI/CD
│       ├── main_informepdf-free.yml.disabled    ← Deshabilitado (App Service legacy)
│       ├── main_informepdf-shiny.yml.disabled   ← Deshabilitado (App Service legacy)
│       └── main_informepdf-uniminuto.yml.disabled ← Deshabilitado (App Service legacy)
│
├── app/
│   ├── app.py                              ← Punto de entrada Shiny (6 854 líneas)
│   ├── styles.css                          ← Estilos personalizados
│   ├── logo_symbiotic.svg                  ← Logo SymbioTIC
│   ├── Logo uniminuto H.png                ← Logo UNIMINUTO
│   └── web_report_demo/
│       ├── viewer.html                     ← Plantilla de vista previa del informe
│       └── viewer_comp.html                ← Plantilla de informe comparativo
│
└── data/                                   ← Archivos de datos (incluidos en la imagen)
    ├── df_SNIES_Programas.parquet
    ├── df_Cobertura_distinct.parquet
    ├── df_PCurso_agg.parquet
    ├── df_Matricula_agg.parquet
    ├── df_Graduados_agg.parquet
    ├── df_OLE_Movilidad_M0.parquet
    ├── df_OLE_Salario_M0.parquet
    ├── df_OLE_Movilidad.parquet
    ├── df_OLE_Salario.parquet
    ├── df_SPADIES_Desercion.parquet
    ├── df_SPADIES_Retencion.parquet
    ├── df_SaberPRO.parquet                 ← 41 MB — el más grande
    ├── df_SaberPRO_mean.parquet
    ├── DIVIPOLA.xlsx
    ├── SalarioMinimo.xlsx
    └── inflacion_anual.xlsx
```

---

## Dockerfile (versión de producción)

Este es el Dockerfile activo. No modificar sin entender las razones de cada sección.

```dockerfile
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# Layer 1: Python packages
# Copy requirements first so Docker can cache this layer independently of app code.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Layer 2: OS-level libraries
# playwright install-deps resolves the correct Chromium library list for the
# current Debian release automatically — handles Bookworm's libasound2 rename.
# The three extra packages cover WeasyPrint font rendering (not in Playwright's list).
RUN apt-get update \
 && python -m playwright install-deps chromium \
 && apt-get install -y --no-install-recommends \
    libpangoft2-1.0-0 \
    shared-mime-info \
    fonts-liberation \
 && rm -rf /var/lib/apt/lists/*

# Layer 3: Chromium browser binary
# Installed to /opt/ms-playwright as root, then made world-readable/executable
# so the non-root runtime user can access it.
RUN python -m playwright install chromium \
 && chmod -R o+rX /opt/ms-playwright

# Runtime: non-root user (UID 1000)
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR $HOME/app
COPY --chown=user . .

EXPOSE 7860
CMD ["python", "-m", "shiny", "run", "app/app.py", "--host", "0.0.0.0", "--port", "7860"]
```

### Decisiones de diseño importantes

| Decisión | Razón |
|---|---|
| `playwright install-deps` se ejecuta como root | Necesita llamar a `apt-get`. Después de `USER user` ya no tendría permisos. |
| `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` | Instala Chromium en una ruta del sistema, no en el home de root, para que el usuario no-root pueda usarlo. |
| `chmod -R o+rX /opt/ms-playwright` | Da permisos de lectura/ejecución al usuario no-root sobre el binario de Chromium. |
| `libpangoft2-1.0-0` agregado manualmente | WeasyPrint necesita este módulo de fuentes de Pango; `playwright install-deps` no lo instala. |
| `libasound2` eliminado | Fue renombrado a `libasound2t64` en Debian Bookworm. `playwright install-deps` instala el nombre correcto automáticamente. |
| `requirements.txt` copiado a `/tmp/` primero | Docker reutiliza el caché de pip si `requirements.txt` no cambió, aunque el código sí cambie. Esto ahorra 5-8 minutos en cada rebuild. |
| Usuario no-root (UID 1000) | Buena práctica de seguridad en contenedores. |
| Puerto 7860 | Estándar de Hugging Face Spaces; el Container App está configurado para aceptar este puerto. |

---

## Workflow de GitHub Actions

Archivo: `.github/workflows/deploy-container-apps.yml`

```yaml
name: Build and Deploy to Azure Container Apps

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGISTRY_NAME: informesmercadoacr
  REGISTRY_LOGIN_SERVER: informesmercadoacr.azurecr.io
  RESOURCE_GROUP: rg-informes-mercado
  CONTAINER_APP_NAME: informes-mercado-app
  IMAGE_NAME: informes-mercado

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to Azure
        uses: azure/login@v1
        with:
          creds: '{"clientId":"${{ secrets.AZURE_CLIENT_ID }}","clientSecret":"${{ secrets.AZURE_CLIENT_SECRET }}","subscriptionId":"${{ secrets.AZURE_SUBSCRIPTION_ID }}","tenantId":"${{ secrets.AZURE_TENANT_ID }}"}'

      - name: Log in to ACR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.REGISTRY_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Deploy to Azure Container Apps
        uses: azure/container-apps-deploy-action@v1
        with:
          resourceGroup: ${{ env.RESOURCE_GROUP }}
          containerAppName: ${{ env.CONTAINER_APP_NAME }}
          imageToDeploy: ${{ env.REGISTRY_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          targetPort: 7860
```

### Notas sobre el workflow

- `azure/login@v1` (no v2) — La v2 eliminó el soporte para JSON como credencial.
  El JSON se construye en línea a partir de los cuatro secretos individuales.
- Cada imagen se taguea con el SHA del commit, no con `latest`.
  Esto permite trazabilidad y rollback a cualquier versión anterior.
- `workflow_dispatch` permite ejecutar el workflow manualmente desde la pestaña Actions sin necesidad de hacer un push.

---

## Flujo de trabajo cotidiano

Cada vez que hagas un cambio en el código:

```bash
git add .
git commit -m "descripción del cambio"
git push origin main
```

GitHub Actions detecta el push y ejecuta automáticamente:

1. Login a Azure y al ACR
2. `docker build` de la imagen (~5-10 min la primera vez, ~3-5 min con caché)
3. `docker push` al registry
4. Actualización del Container App con la nueva imagen

En total: **8-12 minutos** desde el push hasta que la URL pública sirve la nueva versión.

---

## Resolución de paths dentro del contenedor

La app calcula sus rutas relativas a la ubicación de `app.py`:

```python
app_dir  = Path(__file__).parent       # → /home/user/app/app/
data_dir = app_dir.parent / "data"    # → /home/user/app/data/
```

Esto se traduce en la siguiente estructura dentro del contenedor:

```
/home/user/app/                        ← WORKDIR
├── app/
│   ├── app.py                         ← app_dir = aquí
│   ├── styles.css
│   ├── logo_symbiotic.svg
│   └── web_report_demo/
│       ├── viewer.html
│       └── viewer_comp.html
└── data/                              ← data_dir = aquí
    ├── *.parquet
    └── *.xlsx
```

---

## Costos con Azure for Students

| Recurso | Costo mensual aproximado |
|---|---|
| Container Registry Basic | ~$5 USD (cargado al crédito de $100) |
| Container Apps — sin tráfico (`min-replicas 0`) | $0 |
| Container Apps — con tráfico activo | Fracciones de centavo por hora de uso |
| **Total en uso normal (baja frecuencia)** | **~$5 USD/mes** |

> El crédito de Azure for Students es de $100 USD. Con el único costo fijo de $5/mes
> del registry, el crédito dura aproximadamente 20 meses.

---

## Troubleshooting

### Ver logs del contenedor en tiempo real

Desde Azure Cloud Shell:

```bash
az containerapp logs show \
  --name informes-mercado-app \
  --resource-group rg-informes-mercado \
  --follow
```

### La app no inicia (Application Error o pantalla en blanco)

```bash
# Ver los últimos 50 registros
az containerapp logs show \
  --name informes-mercado-app \
  --resource-group rg-informes-mercado \
  --tail 50
```

Causas comunes:
- Un paquete faltante en `requirements.txt` — agrégalo y haz push
- Un archivo de datos que la app intenta leer al arrancar no existe en `data/` — verifica que no esté en `.dockerignore`

### La generación de PDF falla en producción

Verifica que Chromium fue instalado correctamente en la imagen:

```bash
# En Cloud Shell, usando una imagen ya en el registry:
az acr run \
  --registry informesmercadoacr \
  --cmd "python -c \"from playwright.sync_api import sync_playwright; print('Playwright OK')\"" \
  /dev/null
```

### El workflow falla en el paso "Log in to Azure"

Verifica que los cuatro secretos del Service Principal estén correctamente copiados en GitHub:
`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`.
Los valores son los que devolvió `az ad sp create-for-rbac` al crear el Service Principal.

### El workflow falla en el paso "Build and push Docker image"

Verifica que `ACR_USERNAME` y `ACR_PASSWORD` coincidan exactamente con los valores
en Azure Portal → `informesmercadoacr` → Access keys.

### Primera carga lenta (30-60 segundos)

Comportamiento normal con `min-replicas 0`. El contenedor está apagado cuando no hay
tráfico y tarda ese tiempo en encenderse al recibir la primera solicitud. Las cargas
siguientes son inmediatas mientras el contenedor permanezca activo.

### Error de región bloqueada por política de UNIMINUTO

Si algún comando CLI da `RequestDisallowedByPolicy`, verifica que estés usando
`canadacentral` (sin espacios, todo en minúsculas). Todos los recursos de este proyecto
están en esa región.

---

## Comandos de referencia rápida

Todos ejecutables desde **Azure Cloud Shell** (icono `>_` en la barra del portal).

```bash
# Ver el estado general del Container App
az containerapp show \
  --name informes-mercado-app \
  --resource-group rg-informes-mercado \
  --query "{estado:properties.runningStatus, replicas:properties.template.scale, url:properties.configuration.ingress.fqdn}" \
  -o table

# Ver logs en tiempo real
az containerapp logs show \
  --name informes-mercado-app \
  --resource-group rg-informes-mercado \
  --follow

# Forzar un redespliegue con la última imagen del registry (sin cambios en el código)
az containerapp update \
  --name informes-mercado-app \
  --resource-group rg-informes-mercado \
  --image informesmercadoacr.azurecr.io/informes-mercado:latest

# Listar todas las imágenes almacenadas en el registry
az acr repository show-tags \
  --name informesmercadoacr \
  --repository informes-mercado \
  --orderby time_desc \
  --output table

# Eliminar todos los recursos del proyecto (¡irreversible!)
az group delete --name rg-informes-mercado --yes --no-wait
```
