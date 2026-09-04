# MerkaERP 1.3.0+8 — Roadmap Integration Release

Esta versión parte exclusivamente de la 1.2.1+7 confirmada como compilable por el propietario.

La meta de esta entrega no es agregar módulos paralelos sino completar el roadmap dentro de los dominios ya existentes: Nómina dentro de HRM; reposición y control avanzado dentro de Inventario; compras inteligentes dentro de Compras; inteligencia dentro de CRM; diagnóstico dentro de Contabilidad; productividad y periféricos dentro de POS; supervisión dentro de Contratación; salud pública/institucional dentro de Salud y soporte.

Incluye además un gate estático `tool/roadmap_feature_gate.py` que verifica que 26 capacidades clave estén cableadas a la interfaz/dominio correspondiente y no solamente presentes como archivos huérfanos.

El Control Center no forma parte del paquete; únicamente permanecen los contratos de cliente necesarios para integrarlo posteriormente.
