#!/usr/bin/env python3
"""Baixa estabelecimentos do CNES (API de dados abertos do Ministério da Saúde) de um município.

Uso: python3 scripts/data/fetch_cnes.py [--municipio 261110] [--saida data/raw/cnes-261110.json]

O resultado bruto é o insumo do inventário candidato; não é catálogo publicado.
"""

import argparse
import datetime as dt
import json
import sys
import time
import urllib.request
from pathlib import Path

API = "https://apidadosabertos.saude.gov.br/cnes/estabelecimentos"
PAGE = 20  # a API retorna no máximo 20 registros por página


def fetch_page(municipio, offset):
    url = f"{API}?codigo_municipio={municipio}&limit={PAGE}&offset={offset}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return json.load(response)["estabelecimentos"]
        except Exception as error:  # rede instável: repetir com espera crescente
            if attempt == 4:
                raise
            print(f"offset {offset}: {error}; nova tentativa", file=sys.stderr)
            time.sleep(2 ** attempt)
    return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--municipio", default="261110", help="código IBGE de 6 dígitos (Petrolina: 261110)")
    parser.add_argument("--saida")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = Path(args.saida) if args.saida else root / "data" / "raw" / f"cnes-{args.municipio}.json"

    records = []
    offset = 0
    while True:
        page = fetch_page(args.municipio, offset)
        records.extend(page)
        if len(page) < PAGE:
            break
        offset += PAGE
    unique = {r["codigo_cnes"]: r for r in records}
    payload = {
        "fonte": API,
        "codigo_municipio": args.municipio,
        "consultado_em": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "total": len(unique),
        "estabelecimentos": sorted(unique.values(), key=lambda r: r["codigo_cnes"]),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(unique)} estabelecimentos gravados em {output.relative_to(root)}")


if __name__ == "__main__":
    main()
