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
