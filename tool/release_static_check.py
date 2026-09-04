#!/usr/bin/env python3
"""Static release guard for MerkaERP when Flutter SDK is not available.

This does not replace `flutter analyze`, `flutter test` or release builds. It
asserts security/integrity invariants that are easy to regress accidentally.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND_PRESENT = (ROOT / 'backend').is_dir()
failures: list[str] = []


def text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def require(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def require_contains(rel: str, needle: str, message: str) -> None:
    require(needle in text(rel), f"{message} [{rel}]")


def require_absent(rel: str, needle: str, message: str) -> None:
    require(needle not in text(rel), f"{message} [{rel}]")


# Secrets / weak defaults. The Control Center is a separate deliverable;
# when its source is present we still verify the historical hardening invariants,
# while an app-only MerkaERP package is valid without the backend directory.
if BACKEND_PRESENT:
    for rel in ("backend/src/routes/auth.js", "backend/src/database/db.js"):
        require_absent(rel, "admin123", "Known weak bootstrap/login password reappeared")
require(not (ROOT / ".env").exists(), "Root .env must not be packaged")
if BACKEND_PRESENT:
    require(not (ROOT / "backend/.env").exists(), "Backend .env must not be packaged")

# Android network capability.
require_contains(
    "android/app/src/main/AndroidManifest.xml",
    "android.permission.INTERNET",
    "Android release manifest is missing INTERNET permission",
)

# DIAN / external payments fail closed.
require_absent(
    "lib/core/invoicing/dian_transmission_client_noop.dart",
    "TransmissionStatus.simulated",
    "NoOp DIAN transport must not report simulated transmission",
)
payments = text("lib/core/payments/payment_service.dart")
checkout = text("lib/integrations/application/payment_checkout_service.dart")
require("pending_external_confirmation" in payments, "Remote checkout creation must never imply payment completion")
require("verifyAndCompleteRemoteTransaction" in payments, "Remote payments need an authenticated completion path")
require("verification_source" in payments and "provider_verified" in payments, "Remote completed status must be tied to provider verification")
for method in ("verifyStripeIntent", "verifyPayPalOrder", "verifyMercadoPagoPayment"):
    require(method in checkout, f"Missing remote payment verification method: {method}")
require("expectedAmount" in checkout, "Remote payment verification must compare expected amount")
require("remoteCurrency == expectedAmount.currencyCode.toUpperCase()" in checkout, "Remote payment verification must compare currency")

# Sync architecture: dedicated transport tables and no operational pull/apply.
sync = text("lib/services/sync_service.dart")
require("control_center_sync_outbox" in sync, "Control Center transport must use a dedicated outbox")
require("sync_remote_apply_enabled" not in sync, "Remote operational apply must not be config-toggleable")
require("Future<void> _pullChanges" not in sync, "Unsafe remote pull/apply path must remain retired")
require("_applyRemoteChange" not in sync, "Direct remote table mutation path must remain retired")

# Control Center endpoint must not permit clear-text remote transport.
require_contains(
    "lib/services/control_center_endpoint.dart",
    "isLocalDevelopment",
    "Control Center endpoint must only permit HTTP for loopback development",
)
require_contains(
    "lib/services/sync_service.dart",
    "ControlCenterEndpoint.normalize(endpoint)",
    "Persisted sync endpoints must be normalized/validated before storage",
)

# Local database truthfulness and secure secret storage.
require_contains(
    "lib/core/security/database_encryption_service.dart",
    "sqlite-plaintext",
    "Main SQLite encryption status must remain truthful until SQLCipher/SQLite3MC is integrated",
)
require_contains(
    "lib/services/control_center_secret_store.dart",
    "FlutterSecureStorage",
    "Control Center secrets must use secure storage",
)

# Public-sector field encryption: authenticated envelope + unsafe rotation disabled.
enc = text("lib/sector_publico/security/encryption_service.dart")
require("AES-256-CBC-HMAC-SHA256" in enc, "Sensitive-field encryption must authenticate new ciphertext")
require("IV aleatorio" in enc, "Sensitive-field encryption must use per-record random IVs")
require("Rotación de clave deshabilitada" in enc, "Unsafe key rotation must remain fail-closed")

# Webhooks must actually use the delivery service, not audit-only simulation.
require_contains(
    "lib/db_helper.dart",
    "WebhookService.instance.triggerEvent",
    "Database webhook dispatch must use the real delivery service",
)
require_contains(
    "lib/core/webhooks/webhook_service.dart",
    "UPDATE webhooks SET url = target_url",
    "Legacy webhook schema migration must be preserved",
)

# No fake TRM.
require_absent("lib/db_helper.dart", "'rate_to_base': 1.0", "Automatic TRM must not invent a 1.0 rate")

# Audit chain must recompute hashes rather than only compare links.
audit_candidates = list((ROOT / "lib/sector_publico").rglob("*.dart"))
audit_blob = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in audit_candidates)
require(
    "hashCalculado" in audit_blob or "hash_calculado" in audit_blob or "calcularHash" in audit_blob,
    "Public-sector audit verification should contain hash recomputation logic",
)

# Backend hardening signals are checked only when that separate product is
# present in the tree. The MerkaERP desktop release itself does not embed it.
if BACKEND_PRESENT:
    require_contains("backend/src/routes/db_routes.js", "requireSuperAdmin", "Raw DB routes must require superadmin")
    require_contains("backend/src/server.js", "helmet()", "Helmet must remain enabled")
    require_contains("backend/src/server.js", "LICENSE_ACTIVATION_RATE_LIMIT", "License activation rate limit must remain enabled")
    require_contains("backend/src/security/jwt_rs256.js", "CLIENT_PINNED_PUBLIC_KEY_SHA256", "Backend must enforce client-pinned RS256 key")
    require_contains("backend/src/security/remote_commands.js", "timingSafeEqual", "Remote command signature comparison must be constant-time")

    # Exact-money canonical columns in the separate Control Center.
    backend_db = text("backend/src/database/db.js")
    for col in ("contract_value_minor", "total_minor", "amount_minor"):
        require(col in backend_db, f"Control Center exact-money column missing: {col}")

# Product-family isolation and migration safety.
require_contains(
    "lib/features/company_configuration_service.dart",
    "enforceProductFamily",
    "Licensed Commercial/Public feature isolation must remain enforced at persistence boundary",
)
require_contains(
    "lib/onboarding/onboarding_page.dart",
    "licencia?.productFamily",
    "Onboarding must derive product family from the signed license",
)
require_contains(
    "lib/data_migration/application/data_migration_service.dart",
    "importLegacyDocumentFolder",
    "Legacy document migration into SGDEA must remain available",
)
require_contains(
    "lib/data_migration/application/data_migration_service.dart",
    "fue modificado después de la migración",
    "Migration rollback must refuse to erase records modified after import",
)
require_contains(
    "lib/data_migration/application/data_migration_service.dart",
    "fue vinculado posteriormente a otro expediente",
    "Document rollback must refuse to erase documents reused after migration",
)
require_contains(
    "lib/core/go_live/go_live_service.dart",
    "MERKAERP_GO_LIVE_REPORT_1",
    "Go-Live evidence export must remain available",
)

# Known compile regression from the audit.
require_contains("lib/core/api/api_dispatcher.dart", "taxAmount:", "PurchaseItemInput taxAmount regression reappeared")

# No private keys in text files in the delivery tree (excluding git/caches).
private_key_rx = re.compile(r"-----BEGIN (?:RSA )?PRIVATE KEY-----")
for p in ROOT.rglob("*"):
    if not p.is_file() or any(part in {".git", "node_modules", "build", ".dart_tool"} for part in p.parts):
        continue
    if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".rar", ".exe", ".dll"}:
        continue
    try:
        body = p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        continue
    if private_key_rx.search(body):
        failures.append(f"Private key material found in {p.relative_to(ROOT)}")

if failures:
    print("STATIC RELEASE CHECK FAILED")
    for item in failures:
        print(f" - {item}")
    sys.exit(1)

print("Static release check passed.")
print("Reminder: still run flutter analyze, flutter test and release builds with the real Flutter toolchain.")
