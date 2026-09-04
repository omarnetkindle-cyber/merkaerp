#!/usr/bin/env python3
"""MerkaERP roadmap integration gate.

Checks that the major product improvements are not merely present as orphan files,
but are wired into the natural module where the user expects to find them.
This is intentionally static so it can run without Flutter/Dart in support/audit
environments. It complements, but never replaces, flutter analyze/test/build.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def contains(path: str, *needles: str) -> tuple[bool, str]:
    target = ROOT / path
    if not target.exists():
        return False, f"missing file: {path}"
    text = target.read_text(encoding="utf-8", errors="replace")
    missing = [n for n in needles if n not in text]
    if missing:
        return False, f"{path} missing: {', '.join(missing)}"
    return True, path


CHECKS: list[tuple[str, str, tuple[str, ...]]] = [
    ("Backups · retention / integral recovery", "lib/respaldos_page.dart", ("FullBackupService", "applyRetention", "7, 30, 90")),
    ("Health center · app", "lib/core/support/support_center_page.dart", ("HealthReporter", "Restore", "license")),
    ("Cash · user shift lifecycle", "lib/cierres_caja_page.dart", ("CashShiftService", "openShift", "closeCurrentShift", "reopenLastShift")),
    ("Audit · suspicious operations", "lib/auditoria_page.dart", ("AuditRiskPage", "device_id", "old_values", "new_values")),
    ("Alerts · operational engine", "lib/services/merka_intelligence_service.dart", ("alert", "stock", "backup", "license")),
    ("Dashboard · business health", "lib/ui/widgets/workspace_widgets.dart", ("¿Cómo va mi empresa?",)),
    ("Reports · configurable designer", "lib/reportes_page.dart", ("ConfigurableReportPage",)),
    ("PDF documents · company layout", "lib/templates_page.dart", ("Diseño PDF", "QR", "firma")),
    ("POS · peripherals", "lib/ventas_page.dart", ("PosPeripheralsPage", "PosPeripheralService")),
    ("POS · favorites/suspend/shortcuts", "lib/ventas_page.dart", ("PosSessionService", "F2", "F4", "F8", "F10")),
    ("Inventory · control center", "lib/inventario_page.dart", ("InventoryControlCenterPage",)),
    ("Purchases · intelligent suggestions", "lib/compras_page.dart", ("PurchaseIntelligencePage",)),
    ("CRM · customer intelligence", "lib/crm/pages/crm_account_page.dart", ("CrmIntelligencePage",)),
    ("WhatsApp · official communication service", "lib/integrations/application/communication_service.dart", ("sendWhatsAppText", "sendWhatsAppDocument")),
    ("Accounting · diagnostic", "lib/contabilidad_page.dart", ("AccountingDiagnosticPage",)),
    ("HRM · payroll consolidated", "lib/hrm/pages/hrm_employee_page.dart", ("NominaPage(embedded: true)",)),
    ("HRM · electronic payroll", "lib/nomina_page.dart", ("ElectronicPayrollPanel",)),
    ("DIAN/PTA · integration contract", "lib/integrations/application/integration_settings_service.dart", ("dian",)),
    ("Updater · signed/verified service", "lib/services/update_service.dart", ("sha256",)),
    ("Copilot · business health", "lib/core/copilot/copilot_orchestrator.dart", ("business_health", "purchase_suggestions", "crm_customer_risk")),
    ("Public · contractual supervision", "lib/sector_publico/contratacion/pages/contratacion_publica_page.dart", ("SupervisionContractualPage",)),
    ("Public · institutional health", "lib/core/support/support_center_page.dart", ("PublicSectorHealthService",)),
    ("Public · SGR biennia", "lib/sector_publico/regalias/pages/regalias_sgp_page.dart", ("Bienios SGR",)),
    ("Public · document management / SGDEA", "lib/document_management/pages/document_management_page.dart", ("Gestión Documental · SGDEA",)),
    ("Product family · license-routed selector", "lib/core/workspace/selector_modo_screen.dart", ("licencia.productFamily", "ProductFamily.publicSector")),
]


def main() -> int:
    failures: list[str] = []
    print("MerkaERP roadmap integration gate")
    print(f"Root: {ROOT}")
    for label, path, needles in CHECKS:
        ok, detail = contains(path, *needles)
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label}: {detail}")
        if not ok:
            failures.append(label)

    # Structural DB guarantees required by multiple roadmap features.
    db = ROOT / "lib/db_helper.dart"
    db_text = db.read_text(encoding="utf-8", errors="replace") if db.exists() else ""
    db_needles = ("schemaVersion = 111", "stock_minimo", "stock_maximo", "lead_time_days", "device_id")
    db_missing = [n for n in db_needles if n not in db_text]
    if db_missing:
        failures.append("Database roadmap schema")
        print(f"[FAIL] Database roadmap schema: missing {', '.join(db_missing)}")
    else:
        print("[PASS] Database roadmap schema: v111 + tenant isolation + inventory policy + audit device fingerprint")

    if failures:
        print(f"\nROADMAP GATE FAILED: {len(failures)} check(s)")
        for failure in failures:
            print(f" - {failure}")
        return 1
    print(f"\nROADMAP GATE PASS: {len(CHECKS) + 1} checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
