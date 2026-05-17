# frontend/ — Agentes

Parte del workspace **VendIA**. Este repo (app Flutter `vendia_pos`) sigue el
flujo Spec-Driven del workspace.

Lee, en orden:

1. [`../CONSTITUTION.md`](../CONSTITUTION.md) — principios no negociables.
2. [`../AGENTS.md`](../AGENTS.md) — flujo specify → clarify → plan → tasks →
   implement → analyze.
3. [`CLAUDE.md`](CLAUDE.md) — contexto técnico Flutter y adaptación del flujo SDD.
4. [`DESIGN.md`](DESIGN.md) y [`UI_RULES.md`](UI_RULES.md) — obligatorios antes
   de tocar `lib/screens/**` o `lib/widgets/**`.

Regla mínima: ningún cambio de pantalla, flujo o contrato sin un `spec` en
`../specs/`.
