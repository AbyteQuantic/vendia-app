#!/usr/bin/env bash
# Guard de CI: prohíbe `catch` con cuerpo vacío en la capa de persistencia
# (lib/database). Un catch que envuelve una escritura local DEBE relanzar o
# loguear con contexto — NUNCA un cuerpo vacío. Ese patrón fue la causa raíz de
# los bugs de pérdida de datos: convertía un fallo recuperable (red caída,
# serialización) en pérdida silenciosa con falso "guardado".
set -euo pipefail

hits=$(grep -rnE 'catch *\([^)]*\) *\{ *\}' lib/database/ || true)
if [ -n "$hits" ]; then
  echo "❌ catch vacío en la capa de persistencia (riesgo de pérdida silenciosa):"
  echo "$hits"
  echo "→ Relanza el error o loguéalo con contexto; nunca lo tragues en silencio."
  exit 1
fi
echo "✅ sin catch silencioso en lib/database"
