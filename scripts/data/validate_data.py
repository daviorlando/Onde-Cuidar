#!/usr/bin/env python3
"""Valida o catálogo publicado e o pacote viário embarcado; sem rede.

Uso: python3 scripts/data/validate_data.py
Verifica esquema v1, enums, IDs, relacionamentos, proveniência, telefone,
coordenadas, cópia embarcada no app e hashes do pacote de rotas.
"""

import gzip
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog" / "catalog.json"
EMBEDDED = ROOT / "app" / "assets" / "catalog" / "catalog.json"
ROUTING = ROOT / "app" / "assets" / "routing"
TRI = {"yes", "no", "unknown"}
NATURE = {"public", "private", "unknown"}
REVIEW = {"pending", "approved"}
VERSION = re.compile(r"^\d{4}-\d{2}-\d{2}\.\d+$")
ID = re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")


def check_catalog(errors):
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if catalog.get("schema_version") != 1:
        errors.append("schema_version deve ser 1")
    if not VERSION.match(catalog.get("catalog_version", "")):
        errors.append("catalog_version fora do padrão AAAA-MM-DD.N")
    sources = {s["id"] for s in catalog["sources"]}
    services = {s["id"] for s in catalog["services"]}
    specialties = {s["id"] for s in catalog["specialties"]}
    plans = {p["id"] for p in catalog["plans"]}
    seen = set()
    for f in catalog["facilities"]:
        where = f.get("id", "?")
        if not ID.match(f.get("id", "")):
            errors.append(f"{where}: ID inválido")
        if f["id"] in seen:
            errors.append(f"{where}: ID duplicado")
        seen.add(f["id"])
        for key in ("name",):
            if not (f.get(key) or "").strip():
                errors.append(f"{where}: {key} obrigatório")
        address = f.get("address") or {}
        for key in ("street", "city", "state"):
            if not (address.get(key) or "").strip():
                errors.append(f"{where}: address.{key} obrigatório")
        if f.get("status") != "active":
            errors.append(f"{where}: somente unidades ativas são publicadas")
        if f.get("administrative_nature") not in NATURE:
            errors.append(f"{where}: natureza inválida")
        if f.get("review_status") not in REVIEW:
            errors.append(f"{where}: review_status inválido")
        for key in ("sus_access", "is_24h"):
            if f.get(key) not in TRI:
                errors.append(f"{where}: {key} deve ser yes/no/unknown")
        phone = f.get("phone")
        if phone is not None and not re.fullmatch(r"\d{10,11}", phone):
            errors.append(f"{where}: telefone fora do formato")
        loc = f.get("location")
        if loc is not None and not (-90 <= loc["lat"] <= 90 and -180 <= loc["lon"] <= 180):
            errors.append(f"{where}: coordenada inválida")
        if not f.get("provenance"):
            errors.append(f"{where}: sem proveniência")
        for p in f.get("provenance", []):
            if p.get("source_id") not in sources:
                errors.append(f"{where}: fonte inexistente {p.get('source_id')}")
        for s in f.get("services", []):
            if s.get("service_id") not in services:
                errors.append(f"{where}: serviço inexistente {s.get('service_id')}")
            if s.get("availability") not in TRI or s.get("is_24h") not in TRI:
                errors.append(f"{where}: serviço com valor triestado inválido")
        for s in f.get("specialties", []):
            if s.get("specialty_id") not in specialties:
                errors.append(f"{where}: especialidade inexistente")
        for p in f.get("plan_acceptance", []):
            if p.get("plan_id") not in plans or p.get("accepted") not in TRI:
                errors.append(f"{where}: aceitação de plano inválida")
    coverage = catalog["coverage"]
    if coverage["published"] != len(catalog["facilities"]):
        errors.append("coverage.published diferente do número de unidades")
    reviewed = sum(1 for f in catalog["facilities"] if f["review_status"] == "approved")
    if coverage["reviewed"] != reviewed:
        errors.append("coverage.reviewed diferente das unidades aprovadas")
    if EMBEDDED.read_bytes() != CATALOG.read_bytes():
        errors.append("app/assets/catalog/catalog.json difere de data/catalog/catalog.json")
    return len(catalog["facilities"])


def check_routing(errors):
    manifest_path = ROUTING / "manifest.json"
    package_path = ROUTING / "petrolina-car.ocrg.gz"
    if not manifest_path.exists() or not package_path.exists():
        errors.append("pacote viário ausente em app/assets/routing")
        return None
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    compressed = package_path.read_bytes()
    if len(compressed) != manifest["compressed_bytes"] or hashlib.sha256(compressed).hexdigest() != manifest["compressed_sha256"]:
        errors.append("pacote viário comprimido não confere com o manifesto")
        return None
    raw = gzip.decompress(compressed)
    if len(raw) != manifest["bytes"] or hashlib.sha256(raw).hexdigest() != manifest["sha256"]:
        errors.append("pacote viário descomprimido não confere com o manifesto")
    if raw[:4] != b"OCRG":
        errors.append("pacote viário sem assinatura OCRG")
    version, nodes, edges = struct.unpack_from("<III", raw, 4)
    if (version, nodes, edges) != (manifest["format_version"], manifest["nodes"], manifest["edges"]):
        errors.append("cabeçalho do pacote viário diverge do manifesto")
    return manifest


def main():
    errors = []
    count = check_catalog(errors)
    manifest = check_routing(errors)
    if errors:
        print("Validação de dados falhou:")
        for e in errors:
            print(f"- {e}")
        return 1
    print(f"OK: catálogo com {count} unidades; pacote viário "
          f"{manifest['version']} ({manifest['nodes']} nós, {manifest['edges']} arestas).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
