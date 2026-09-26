#!/usr/bin/env python3
"""Gera inventário candidato e catálogo v1 a partir do CNES bruto.

Uso: python3 scripts/data/build_catalog.py [--versao 2026-09-23.1]

Entradas: data/raw/cnes-261110.json (scripts/data/fetch_cnes.py) e, se existir,
data/raw/petrolina-limite.json (polígono municipal, scripts/data/build_road_graph.py).
Saídas:
- data/inventory/inventario-cnes-petrolina.csv: todos os estabelecimentos, com
  decisão de inclusão/exclusão e motivo (colunas da ficha de coleta + controle);
- data/catalog/catalog.json: registros incluídos, todos com revisão pendente.

Nada é inferido além do que o cadastro informa: campos ausentes ficam nulos/desconhecidos.
"""

import argparse
import csv
import datetime as dt
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "raw" / "cnes-261110.json"
BOUNDARY = ROOT / "data" / "raw" / "petrolina-limite.json"
INVENTORY = ROOT / "data" / "inventory" / "inventario-cnes-petrolina.csv"
CATALOG = ROOT / "data" / "catalog" / "catalog.json"

SOURCE_ID = "cnes-dados-abertos"

# Tabela TP_UNIDADE do CNES (códigos presentes ou esperados no município).
CNES_TYPES = {
    1: "Posto de saúde",
    2: "Centro de saúde / Unidade básica",
    4: "Policlínica",
    5: "Hospital geral",
    7: "Hospital especializado",
    15: "Unidade mista",
    20: "Pronto-socorro geral",
    21: "Pronto-socorro especializado",
    22: "Consultório isolado",
    36: "Clínica / centro de especialidade",
    39: "Unidade de apoio diagnose e terapia (SADT isolado)",
    40: "Unidade móvel terrestre",
    42: "Unidade móvel de nível pré-hospitalar (urgência)",
    43: "Farmácia",
    50: "Unidade de vigilância em saúde",
    60: "Cooperativa ou empresa de cessão de trabalhadores",
    61: "Centro de parto normal isolado",
    62: "Hospital-dia isolado",
    64: "Central de regulação de serviços de saúde",
    68: "Central de gestão em saúde",
    69: "Centro de atenção hemoterápica / hematológica",
    70: "Centro de atenção psicossocial (CAPS)",
    71: "Centro de apoio à saúde da família",
    72: "Unidade de atenção à saúde indígena",
    73: "Pronto atendimento",
    74: "Polo Academia da Saúde",
    75: "Telessaúde",
    76: "Central de regulação médica das urgências",
    77: "Serviço de atenção domiciliar isolado",
    78: "Unidade de atenção em regime residencial",
    79: "Oficina ortopédica",
    80: "Laboratório de saúde pública",
    81: "Central de regulação do acesso",
    82: "Central de notificação, captação e distribuição de órgãos",
    83: "Polo de prevenção de doenças e agravos",
    84: "Central de abastecimento",
    85: "Centro de imunização",
}

# Critério de inclusão v1: estabelecimentos fixos com atendimento direto ao público.
# Serviço derivado do tipo de estabelecimento (categoria "atendimento").
TYPE_SERVICE = {
    1: "atencao-basica",
    2: "atencao-basica",
    4: "ambulatorio-especialidades",
    5: "hospital",
    7: "hospital",
    15: "hospital",
    20: "urgencia-emergencia",
    21: "urgencia-emergencia",
    36: "ambulatorio-especialidades",
    39: "exames-terapias",
    61: "parto-normal",
    62: "hospital-dia",
    69: "hemoterapia",
    70: "saude-mental",
    73: "urgencia-emergencia",
    85: "vacinacao",
}

SERVICES = [
    ("atencao-basica", "Atenção básica (UBS / posto)", "atendimento", ["ubs", "posto", "postinho", "psf", "saude da familia"]),
    ("urgencia-emergencia", "Urgência e emergência", "atendimento", ["upa", "pronto atendimento", "pronto socorro", "emergencia"]),
    ("hospital", "Hospital", "atendimento", ["hospital"]),
    ("hospital-dia", "Hospital-dia", "atendimento", []),
    ("ambulatorio-especialidades", "Clínica / ambulatório de especialidades", "atendimento", ["clinica", "consulta", "especialista", "policlinica"]),
    ("exames-terapias", "Exames e terapias (diagnóstico)", "atendimento", ["exame", "laboratorio", "imagem", "raio x", "ultrassom"]),
    ("saude-mental", "Saúde mental (CAPS)", "atendimento", ["caps", "psicossocial"]),
    ("hemoterapia", "Hemoterapia / hematologia", "atendimento", ["hemocentro", "sangue"]),
    ("parto-normal", "Centro de parto normal", "atendimento", ["parto"]),
    ("vacinacao", "Vacinação", "atendimento", ["vacina", "imunizacao"]),
    ("internacao", "Internação hospitalar", "estrutura", ["internamento", "leito"]),
    ("centro-cirurgico", "Centro cirúrgico", "estrutura", ["cirurgia"]),
    ("centro-obstetrico", "Centro obstétrico", "estrutura", ["maternidade", "obstetricia", "parto"]),
    ("unidade-neonatal", "Unidade neonatal", "estrutura", ["neonatal", "recem nascido"]),
]

FLAG_SERVICE = {
    "estabelecimento_possui_atendimento_hospitalar": "internacao",
    "estabelecimento_possui_centro_cirurgico": "centro-cirurgico",
    "estabelecimento_possui_centro_obstetrico": "centro-obstetrico",
    "estabelecimento_possui_centro_neonatal": "unidade-neonatal",
}

TURN_24H = "ATENDIMENTO CONTINUO DE 24 HORAS/DIA (PLANTAO:INCLUI SABADOS, DOMINGOS E FERIADOS)"
TURN_NOT_24H = {
    "ATENDIMENTOS NOS TURNOS DA MANHA E A TARDE",
    "ATENDIMENTO NOS TURNOS DA MANHA, TARDE E NOITE",
    "ATENDIMENTO SOMENTE PELA MANHA",
    "ATENDIMENTO SOMENTE A TARDE",
    "ATENDIMENTO SOMENTE A NOITE",
}

# Caixa envolvente do município, usada se o polígono não estiver disponível.
PETROLINA_BBOX = (-9.95, -41.25, -8.55, -40.20)  # sul, oeste, norte, leste

INVENTORY_COLUMNS = [
    "id", "cnes", "nome", "natureza_administrativa", "acesso_sus", "logradouro", "numero",
    "complemento", "bairro_localidade", "cep", "municipio", "uf", "telefone", "latitude",
    "longitude", "precisao_geografica", "servico", "especialidade", "horario", "servico_24h",
    "plano", "status_plano", "forma_acesso", "fonte", "consultado_em", "verificado_em",
    "status_revisao", "observacoes", "tipo_cnes", "decisao", "motivo",
]


def clean(value):
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    return text or None


def nature(record):
    code = clean(record.get("descricao_natureza_juridica_estabelecimento"))
    if not code or not code[0].isdigit():
        return "unknown"
    # Natureza jurídica (IBGE/CONCLA): 1xxx administração pública; 2xxx empresas;
    # 3xxx entidades sem fins lucrativos; 4xxx pessoas físicas.
    return {"1": "public", "2": "private", "3": "private", "4": "private"}.get(code[0], "unknown")


def sus_access(record):
    flag = clean(record.get("estabelecimento_faz_atendimento_ambulatorial_sus"))
    if flag == "SIM":
        return "yes"
    if flag == "NAO" and not record.get("estabelecimento_possui_atendimento_hospitalar"):
        # O indicador cobre atendimento ambulatorial; hospitais podem ter internação SUS.
        return "no"
    return "unknown"


def is_24h(record):
    turn = clean(record.get("descricao_turno_atendimento"))
    if turn == TURN_24H:
        return "yes"
    if turn in TURN_NOT_24H:
        return "no"
    return "unknown"


def phone(record):
    digits = re.sub(r"\D", "", record.get("numero_telefone_estabelecimento") or "")
    if digits.startswith("0"):
        digits = digits.lstrip("0")
    if len(digits) == 8:  # sem DDD: todos os registros são de Petrolina (DDD 87)
        digits = "87" + digits
    if len(digits) in (10, 11) and digits[:2] == "87":
        return digits
    return None


def point_in_ring(lat, lon, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        yi, xi = ring[i]
        yj, xj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def load_boundary():
    if not BOUNDARY.exists():
        return None
    data = json.loads(BOUNDARY.read_text(encoding="utf-8"))
    return data["outer_rings"]


def inside_municipality(lat, lon, rings):
    if rings:
        return any(point_in_ring(lat, lon, ring) for ring in rings)
    south, west, north, east = PETROLINA_BBOX
    return south <= lat <= north and west <= lon <= east


def location(record, rings):
    lat = record.get("latitude_estabelecimento_decimo_grau")
    lon = record.get("longitude_estabelecimento_decimo_grau")
    if lat is None or lon is None:
        return None, "sem coordenada no cadastro"
    if not (-90 <= lat <= 90 and -180 <= lon <= 180) or not inside_municipality(lat, lon, rings):
        return None, "coordenada do cadastro fora do limite municipal (OSM); descartada para rota até conferência"
    return {"lat": round(lat, 7), "lon": round(lon, 7), "accuracy": "cadastro_cnes"}, None


def decide(record):
    reason_code = clean(record.get("codigo_motivo_desabilitacao_estabelecimento"))
    if reason_code:
        return "excluido", f"desabilitado no CNES (motivo {reason_code})"
    tipo = record.get("codigo_tipo_unidade")
    if tipo not in TYPE_SERVICE:
        return "excluido", f"tipo {tipo} fora do critério de inclusão v1"
    if not clean(record.get("nome_fantasia")) and not clean(record.get("nome_razao_social")):
        return "excluido", "sem nome"
    if not clean(record.get("endereco_estabelecimento")):
        return "excluido", "sem endereço"
    return "incluido", ""


def facility(record, consulted_at, rings):
    code = str(record["codigo_cnes"]).zfill(7)
    loc, loc_note = location(record, rings)
    type_code = record["codigo_tipo_unidade"]
    h24 = is_24h(record)
    services = [{"service_id": TYPE_SERVICE[type_code], "availability": "yes", "is_24h": h24, "source_id": SOURCE_ID}]
    for flag, service_id in FLAG_SERVICE.items():
        if record.get(flag) == 1 and service_id not in {s["service_id"] for s in services}:
            services.append({"service_id": service_id, "availability": "yes", "is_24h": "unknown", "source_id": SOURCE_ID})
    notes = [n for n in [loc_note] if n]
    return {
        "id": f"cnes-{code}",
        "cnes": code,
        "name": clean(record.get("nome_fantasia")) or clean(record.get("nome_razao_social")),
        "legal_name": clean(record.get("nome_razao_social")),
        "administrative_nature": nature(record),
        "sus_access": sus_access(record),
        "status": "active",
        "review_status": "pending",
        "facility_type": {"code": type_code, "name": CNES_TYPES.get(type_code, f"Tipo {type_code}")},
        "address": {
            "street": clean(record.get("endereco_estabelecimento")),
            "number": clean(record.get("numero_estabelecimento")),
            "complement": None,
            "locality": clean(record.get("bairro_estabelecimento")),
            "postal_code": clean(record.get("codigo_cep_estabelecimento")),
            "city": "Petrolina",
            "state": "PE",
        },
        "phone": phone(record),
        "location": loc,
        "timezone": "America/Recife",
        "is_24h": h24,
        "hours_description": clean(record.get("descricao_turno_atendimento")),
        "access_instructions": None,
        "services": services,
        "specialties": [],
        "plan_acceptance": [],
        "provenance": [{
            "field": "*",
            "source_id": SOURCE_ID,
            "consulted_at": consulted_at,
            "method": "importacao_cadastro",
            "source_updated_at": clean(record.get("data_atualizacao")),
        }],
        "verified_at": None,
        "notes": notes,
    }


def inventory_row(record, decision, reason, fac, consulted_at):
    tipo = record.get("codigo_tipo_unidade")
    row = {c: "" for c in INVENTORY_COLUMNS}
    row.update({
        "id": f"cnes-{str(record['codigo_cnes']).zfill(7)}",
        "cnes": str(record["codigo_cnes"]).zfill(7),
        "nome": clean(record.get("nome_fantasia")) or clean(record.get("nome_razao_social")) or "",
        "natureza_administrativa": nature(record),
        "acesso_sus": sus_access(record),
        "logradouro": clean(record.get("endereco_estabelecimento")) or "",
        "numero": clean(record.get("numero_estabelecimento")) or "",
        "bairro_localidade": clean(record.get("bairro_estabelecimento")) or "",
        "cep": clean(record.get("codigo_cep_estabelecimento")) or "",
        "municipio": "Petrolina",
        "uf": "PE",
        "telefone": phone(record) or "",
        "latitude": record.get("latitude_estabelecimento_decimo_grau") or "",
        "longitude": record.get("longitude_estabelecimento_decimo_grau") or "",
        "precisao_geografica": "cadastro_cnes" if record.get("latitude_estabelecimento_decimo_grau") else "",
        "servico": ";".join(s["service_id"] for s in fac["services"]) if fac else TYPE_SERVICE.get(tipo, ""),
        "horario": clean(record.get("descricao_turno_atendimento")) or "",
        "servico_24h": is_24h(record),
        "status_plano": "unknown",
        "fonte": f"{SOURCE_ID} (atualizado no CNES em {record.get('data_atualizacao')})",
        "consultado_em": consulted_at,
        "status_revisao": "pendente",
        "observacoes": "; ".join(fac["notes"]) if fac else "",
        "tipo_cnes": f"{tipo} - {CNES_TYPES.get(tipo, 'desconhecido')}",
        "decisao": decision,
        "motivo": reason,
    })
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--versao", help="catalog_version; padrão: data de consulta + .1")
    args = parser.parse_args()
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    consulted_at = raw["consultado_em"]
    rings = load_boundary()
    version = args.versao or f"{consulted_at[:10]}.1"

    rows, facilities = [], []
    for record in raw["estabelecimentos"]:
        decision, reason = decide(record)
        fac = facility(record, consulted_at, rings) if decision == "incluido" else None
        if fac:
            facilities.append(fac)
        rows.append(inventory_row(record, decision, reason, fac, consulted_at))

    INVENTORY.parent.mkdir(parents=True, exist_ok=True)
    with INVENTORY.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=INVENTORY_COLUMNS)
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda r: r["id"]))

    facilities.sort(key=lambda f: f["id"])
    catalog = {
        "schema_version": 1,
        "catalog_version": version,
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "coverage": {
            "municipality": "Petrolina",
            "state": "PE",
            "registry_total": len(rows),
            "eligible_identified": len(facilities),
            "published": len(facilities),
            "reviewed": 0,
            "note": "Estabelecimentos ativos do CNES dentro do critério de inclusão v1. "
                    "Nenhum registro foi confirmado pela curadoria; o CNES não garante telefone, horário ou disponibilidade atual.",
        },
        "sources": [{
            "id": SOURCE_ID,
            "type": "registro_oficial",
            "name": "CNES — API de dados abertos do Ministério da Saúde",
            "reference": raw["fonte"],
            "consulted_at": consulted_at,
        }],
        "services": [{"id": i, "name": n, "category": c, "synonyms": s} for i, n, c, s in SERVICES],
        "specialties": [],
        "plans": [],
        "facilities": facilities,
    }
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    excluded = sum(1 for r in rows if r["decisao"] == "excluido")
    print(f"catálogo {version}: {len(facilities)} incluídos, {excluded} excluídos, polígono={'sim' if rings else 'não (bbox)'}")


if __name__ == "__main__":
    main()
