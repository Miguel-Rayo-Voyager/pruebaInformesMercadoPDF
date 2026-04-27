# Guía de Despliegue: Azure Container Apps con Docker
**Proyecto:** InformePDF - Dashboard de Análisis de Mercado Educativo  
**Framework:** Shiny for Python  
**Plataforma:** Azure Container Apps (Compatible con Azure for Students)  
**Método:** Docker + Azure Container Registry + GitHub Actions  
**Región obligatoria:** Canada Central (política UNIMINUTO)

---

> [!IMPORTANT]
> Esta guía asume que ya tienes:
> - Docker instalado y funcionando en tu PC
> - Azure CLI instalado (`az --version` para verificar)
> - El proyecto subido en GitHub (`miguxldsymbiotic/PruebaInformesMERCADO`)
> - Sesión activa en Azure con tu cuenta de estudiante

---

## ¿Por qué Container Apps y no App Service?

| Característica | App Service F1 | **Container Apps** |
|---|---|---|
| WeasyPrint | ❌ No funciona | ✅ Funciona |
| Playwright + Chromium | ❌ No funciona | ✅ Funciona |
| Typst | ❌ No funciona | ✅ Funciona |
| Control del sistema operativo | ❌ Limitado | ✅ Total (Docker) |
| Costo en Azure for Students | $0 (F1 fijo) | ~$0 con `min-replicas 0` |
| Complejidad | Baja | Media |

La clave del costo cero es `--min-replicas 0`: el contenedor **se apaga solo** cuando no hay visitas y **no consume créditos** en reposo.

---

## Arquitectura del despliegue

```
Tu PC (código)
     │
     │ git push
     ▼
GitHub (repositorio)
     │
     │ GitHub Actions se activa
     ▼
Azure Container Registry (ACR)
     │  Almacena la imagen Docker
     │
     ▼
Azure Container Apps
     │  Corre el contenedor con Shiny
     ▼
URL pública de tu app
```

---

## FASE 0: Archivos que debes agregar al proyecto

Antes de hacer cualquier cosa en Azure, asegúrate de tener estos archivos en la **raíz** de tu repositorio.

### Estructura esperada

```
PruebaInformesMERCADO/
├── app/
│   └── app.py                  ← Punto de entrada Shiny
├── data/                       ← Archivos .parquet y .xlsx
├── requirements.txt            ← DEBE estar en la raíz
├── Dockerfile                  ← Lo crearás en esta fase
├── .dockerignore               ← Ya lo tienes, revisar abajo
└── .github/
    └── workflows/
        └── deploy.yml          ← Lo crearás en la Fase 4
```

### `requirements.txt` (en la raíz)

```txt
faicons
shiny
plotly
polars
pyarrow
pandas
openpyxl
jinja2
weasyprint
playwright
kaleido
ridgeplot
```

> [!NOTE]
> `typst` no es un paquete pip — es un binario. Si lo usas con `subprocess`, se instala
> directamente en el Dockerfile (ver Fase 0.2). Si lo usas de otra forma, ajusta según corresponda.

### `Dockerfile` (en la raíz)

```dockerfile
# Imagen base de Python 3.11 (slim para menor tamaño)
FROM python:3.11-slim

# ─────────────────────────────────────────────
# DEPENDENCIAS DEL SISTEMA
# Necesarias para WeasyPrint, Playwright y Typst
# ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # WeasyPrint (renderizado PDF con CSS)
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    libffi-dev \
    shared-mime-info \
    libcairo2 \
    libcairo-gobject2 \
    # Playwright / Chromium
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libxshmfence1 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxext6 \
    # Fuentes (necesarias para PDF)
    fonts-liberation \
    fonts-dejavu-core \
    # Utilidades generales
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────
# TYPST (binario del sistema)
# Descarga la versión más reciente de Typst
# ─────────────────────────────────────────────
RUN curl -L https://github.com/typst/typst/releases/download/v0.11.1/typst-x86_64-unknown-linux-musl.tar.xz \
    | tar -xJ --strip-components=1 -C /usr/local/bin/ typst-x86_64-unknown-linux-musl/typst \
    && chmod +x /usr/local/bin/typst

# ─────────────────────────────────────────────
# DIRECTORIO DE TRABAJO
# ─────────────────────────────────────────────
WORKDIR /app

# ─────────────────────────────────────────────
# DEPENDENCIAS PYTHON
# Se copian primero para aprovechar el caché de Docker
# Si requirements.txt no cambia, esta capa no se reconstruye
# ─────────────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────
# PLAYWRIGHT + CHROMIUM
# Se instala DESPUÉS de pip para no invalidar el caché de pip
# ─────────────────────────────────────────────
RUN playwright install chromium \
    && playwright install-deps chromium

# ─────────────────────────────────────────────
# CÓDIGO DEL PROYECTO
# Se copia al final para que los cambios de código
# no re-instalen dependencias innecesariamente
# ─────────────────────────────────────────────
COPY . .

# Puerto que expone Shiny
EXPOSE 8000

# ─────────────────────────────────────────────
# COMANDO DE INICIO
# Ajusta 'app/app.py' a la ruta real de tu archivo principal
# ─────────────────────────────────────────────
CMD ["python", "-m", "shiny", "run", "app/app.py", \
     "--host", "0.0.0.0", "--port", "8000"]
```

> [!WARNING]
> **Verifica la ruta `app/app.py`** — si tu archivo principal está en otra ubicación
> (ej: `app.py` en la raíz), cámbiala en el CMD del Dockerfile.

### `.dockerignore` (revisar el tuyo)

Tu `.dockerignore` actual está bien. Solo verifica que las carpetas de datos **no estén excluidas**. El tuyo excluye correctamente solo cosas de desarrollo:

```dockerignore
.git
.gitignore
__pycache__
*.pyc
*.pyo
*.pyd
.db
.ipynb_checkpoints
.venv
venv
.vscode/
Dockerfile
docker-compose.yml
.dockerignore

# App specific — SOLO si no contienen datos necesarios en producción
app/doc-mig/
Adicionales/
dashboard/
temp_report/
web_report_demo/
```

> [!CAUTION]
> Si `Adicionales/`, `dashboard/` o alguna de esas carpetas contienen archivos `.parquet`
> o `.xlsx` que la app necesita en tiempo de ejecución, **quítalas del `.dockerignore`**.
> De lo contrario, la app arrancará pero no encontrará los datos.

---

## FASE 1: Probar Docker localmente

Antes de subir nada a Azure, confirma que el contenedor funciona en tu PC.

```bash
# Desde la raíz del proyecto
docker build -t informepdf-local .

# Ejecutar el contenedor
docker run -p 8000:8000 informepdf-local
```

Abre tu navegador en `http://localhost:8000`. Si la app carga correctamente, el Docker está listo.

**Si hay errores comunes:**

| Error | Causa | Solución |
|---|---|---|
| `ModuleNotFoundError` | Falta una dependencia en requirements.txt | Agrégala y reconstruye |
| `FileNotFoundError` en datos | Carpeta de datos excluida en .dockerignore | Quitar esa carpeta del .dockerignore |
| Puerto ya en uso | Otro proceso usa el 8000 | Cambia `-p 8001:8000` y abre `localhost:8001` |

---

## FASE 2: Crear recursos en Azure

Abre una terminal con Azure CLI y ejecuta los siguientes comandos **en orden**.

### 2.1 — Iniciar sesión

```bash
az login
```

Selecciona tu cuenta de estudiante de UNIMINUTO cuando aparezca el navegador.

### 2.2 — Seleccionar la suscripción correcta

```bash
# Ver todas las suscripciones disponibles
az account list --output table

# Seleccionar Azure for Students
az account set --subscription "Azure for Students"
```

### 2.3 — Crear el Grupo de Recursos

```bash
az group create \
  --name rg-informepdf \
  --location canadacentral
```

> [!NOTE]
> Usamos `canadacentral` (sin espacio, en minúsculas) porque es la única región
> permitida por la política de UNIMINUTO.

### 2.4 — Crear el Azure Container Registry (ACR)

El ACR es el almacén privado donde se guarda tu imagen Docker.

```bash
az acr create \
  --resource-group rg-informepdf \
  --name informepdfregistry \
  --sku Basic \
  --location canadacentral
```

> [!NOTE]
> El nombre `informepdfregistry` debe ser único en todo Azure. Si da error de nombre
> duplicado, prueba con `informepdfuniminuto` o agrega tus iniciales.

```bash
# Habilitar acceso con usuario y contraseña (necesario para GitHub Actions)
az acr update \
  --name informepdfregistry \
  --admin-enabled true
```

### 2.5 — Crear el entorno de Container Apps

```bash
az containerapp env create \
  --name env-informepdf \
  --resource-group rg-informepdf \
  --location canadacentral
```

Este comando tarda 3-5 minutos. Espera a que termine antes de continuar.

---

## FASE 3: Primera subida manual de la imagen

Para verificar que todo funciona antes de configurar el CI/CD automático, sube la imagen manualmente una vez.

```bash
# Login al registry de Azure desde Docker
az acr login --name informepdfregistry

# Construir la imagen con el tag correcto para Azure
# (Azure ACR Build construye en la nube, sin consumir tu internet local para subir)
az acr build \
  --registry informepdfregistry \
  --image informepdf-app:latest \
  --location canadacentral \
  .
```

> [!TIP]
> El comando `az acr build` sube el código fuente a Azure y construye la imagen allá.
> Esto es mucho más rápido que hacer `docker build` local y luego `docker push`, porque
> evita subir los ~300MB de Chromium desde Colombia.

### 3.1 — Crear el Container App

```bash
# Obtener credenciales del registry
ACR_SERVER=$(az acr show --name informepdfregistry --query loginServer -o tsv)
ACR_USER=$(az acr credential show --name informepdfregistry --query username -o tsv)
ACR_PASS=$(az acr credential show --name informepdfregistry --query "passwords[0].value" -o tsv)

# Crear el Container App
az containerapp create \
  --name informepdf-app \
  --resource-group rg-informepdf \
  --environment env-informepdf \
  --image informepdfregistry.azurecr.io/informepdf-app:latest \
  --registry-server informepdfregistry.azurecr.io \
  --registry-username $ACR_USER \
  --registry-password $ACR_PASS \
  --target-port 8000 \
  --ingress external \
  --cpu 1.0 \
  --memory 2.0Gi \
  --min-replicas 0 \
  --max-replicas 1
```

### 3.2 — Obtener la URL pública

```bash
az containerapp show \
  --name informepdf-app \
  --resource-group rg-informepdf \
  --query properties.configuration.ingress.fqdn \
  -o tsv
```

Copia esa URL y ábrela en el navegador. Debería verse tu app de Shiny. 🎉

---

## FASE 4: Automatización con GitHub Actions (CI/CD)

Una vez que la app funciona manualmente, configura el despliegue automático para que cada `git push` actualice la app sola.

### 4.1 — Obtener credenciales para GitHub

```bash
# Credenciales del ACR
az acr credential show --name informepdfregistry
```

Guarda el `username` y el primer `password` — los necesitarás en el siguiente paso.

### 4.2 — Agregar secretos en GitHub

Ve a tu repositorio en GitHub → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Agrega estos tres secretos:

| Nombre del secreto | Valor |
|---|---|
| `REGISTRY_USERNAME` | El username del ACR (del paso anterior) |
| `REGISTRY_PASSWORD` | El password del ACR (del paso anterior) |
| `AZURE_CREDENTIALS` | Ver instrucciones abajo |

**Para `AZURE_CREDENTIALS`**, ejecuta esto en Azure CLI:

```bash
az ad sp create-for-rbac \
  --name "sp-informepdf-github" \
  --role contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-informepdf \
  --sdk-auth
```

Copia el JSON completo que devuelve y pégalo como valor del secreto `AZURE_CREDENTIALS`.

### 4.3 — Crear el workflow de GitHub Actions

Crea el archivo `.github/workflows/deploy.yml` en tu repositorio con este contenido:

```yaml
name: Build and Deploy to Azure Container Apps

on:
  push:
    branches:
      - main

env:
  REGISTRY: informepdfregistry.azurecr.io
  IMAGE_NAME: informepdf-app
  RESOURCE_GROUP: rg-informepdf
  CONTAINER_APP_NAME: informepdf-app

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      # 1. Checkout del código
      - name: Checkout repository
        uses: actions/checkout@v4

      # 2. Login a Azure
      - name: Login to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      # 3. Login al Azure Container Registry
      - name: Login to Azure Container Registry
        uses: azure/docker-login@v1
        with:
          login-server: ${{ env.REGISTRY }}
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}

      # 4. Build y Push de la imagen Docker
      - name: Build and push Docker image
        run: |
          az acr build \
            --registry informepdfregistry \
            --image ${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --image ${{ env.IMAGE_NAME }}:latest \
            .

      # 5. Actualizar el Container App con la nueva imagen
      - name: Deploy to Azure Container Apps
        run: |
          az containerapp update \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.RESOURCE_GROUP }} \
            --image ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

### 4.4 — Hacer el primer push automático

```bash
git add .
git commit -m "feat: configurar CI/CD con Azure Container Apps"
git push origin main
```

Ve a la pestaña **Actions** en GitHub y verás el workflow ejecutándose. En 5-10 minutos estará desplegado.

---

## FASE 5: Flujo de trabajo futuro

```
1. Modificas el código en tu PC
2. git add .
3. git commit -m "descripción del cambio"
4. git push origin main
5. GitHub Actions detecta el push
6. Construye la nueva imagen en ACR (~3-5 min)
7. Actualiza el Container App automáticamente
8. En ~8-10 minutos, la web tiene los cambios
```

---

## Consideraciones de costo con Azure for Students

| Recurso | Costo |
|---|---|
| Container Registry (Basic) | ~$0.17 USD/día (~$5/mes) — consume crédito estudiante |
| Container Apps con `min-replicas 0` | $0 cuando no hay tráfico |
| Container Apps con tráfico | Muy bajo, fracciones de centavo por solicitud |

> [!NOTE]
> El Container Registry Basic cuesta ~$5/mes de tu crédito de $100. Es el único costo fijo.
> Si quieres eliminarlo después de configurar todo, puedes hacer el build manualmente cuando
> necesites actualizar, o buscar alternativas como GitHub Container Registry (ghcr.io) que es gratis.

---

## Troubleshooting: Problemas comunes

### La app no inicia (Application Error)

```bash
# Ver los logs del contenedor en tiempo real
az containerapp logs show \
  --name informepdf-app \
  --resource-group rg-informepdf \
  --follow
```

### La app inicia pero los datos no cargan

Verifica que las carpetas con `.parquet` y `.xlsx` **no están** en el `.dockerignore`.
Reconstruye la imagen después de corregirlo.

### Playwright da error en producción

```bash
# Verifica que el Chromium quedó instalado en la imagen
docker run --rm informepdfregistry.azurecr.io/informepdf-app:latest \
  python -c "from playwright.sync_api import sync_playwright; print('OK')"
```

### Error de región bloqueada por política

Si algún comando da `RequestDisallowedByPolicy`, verifica que estás usando `canadacentral`
(sin espacio, todo en minúsculas).

### El Container App "duerme" y la primera carga es lenta

Es normal con `min-replicas 0`. El primer request tarda 30-60 segundos en "despertar"
el contenedor. Las cargas siguientes son normales. Esto es el tradeoff del costo cero.

---

## Resumen de comandos esenciales

```bash
# Ver estado de la app
az containerapp show --name informepdf-app --resource-group rg-informepdf

# Ver logs en vivo
az containerapp logs show --name informepdf-app --resource-group rg-informepdf --follow

# Actualizar manualmente (sin CI/CD)
az acr build --registry informepdfregistry --image informepdf-app:latest . && \
az containerapp update --name informepdf-app --resource-group rg-informepdf \
  --image informepdfregistry.azurecr.io/informepdf-app:latest

# Eliminar todos los recursos (¡precaución!)
az group delete --name rg-informepdf --yes
```