#!/usr/bin/env python3
"""Gera o pacote viário offline (perfil automóvel) de Petrolina a partir de um extrato OSM.

Requer pyosmium (`pip install osmium`). Uso:
    python3 scripts/data/build_road_graph.py data/raw/osm/nordeste-AAMMDD.osm.pbf \
        [--versao 2026-09-22.1] [--margem-km 5]

Saídas:
- app/assets/routing/petrolina-car.ocrg.gz e manifest.json (pacote regional);
- data/raw/petrolina-limite.json (polígono municipal usado na validação do catálogo).

Formato OCRG v1 (little-endian): 'OCRG', u32 versão, u32 nós, u32 arestas,
i32 bbox (sul, oeste, norte, leste em 1e-7 graus), i32 lat[n], i32 lon[n],
u32 offsets[n+1], u32 destino[m], f32 comprimento_m[m], u8 classe[m].
Arestas são dirigidas (sentido único respeitado); comprimento geodésico.
"""

import argparse
import datetime as dt
import gzip
import hashlib
import json
import math
import struct
import sys
from array import array
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "app" / "assets" / "routing"
BOUNDARY_OUT = ROOT / "data" / "raw" / "petrolina-limite.json"
FORMAT_VERSION = 1

# Pré-filtro generoso ao redor do município (sul, oeste, norte, leste).
PREFILTER = (-10.10, -41.40, -8.40, -40.05)

# Classe usada para nível de detalhe do mapa: 0 = mais importante.
ROAD_CLASS = {
    "motorway": 0, "motorway_link": 0, "trunk": 0, "trunk_link": 0,
    "primary": 1, "primary_link": 1,
    "secondary": 2, "secondary_link": 2,
    "tertiary": 3, "tertiary_link": 3,
    "unclassified": 4, "residential": 4, "living_street": 4, "road": 4,
    "service": 5,
    "track": 6,
}
DENY_ACCESS = {"no", "private", "agricultural", "forestry", "delivery", "emergency"}
ALLOW_ACCESS = {"yes", "permissive", "destination", "designated", "customers"}


def haversine(lat1, lon1, lat2, lon2):
    r = 6371008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def car_allowed(tags):
    highway = tags.get("highway")
    if highway not in ROAD_CLASS:
        return False
    if tags.get("area") == "yes":
        return False
    for key in ("motorcar", "motor_vehicle", "vehicle", "access"):
        value = tags.get(key)
        if value in ALLOW_ACCESS:
            return True
        if value in DENY_ACCESS:
            return False
    return True


def direction(tags):
    """(para frente, para trás) permitidos para automóvel."""
    oneway = tags.get("oneway:motorcar") or tags.get("oneway")
    if oneway in ("yes", "true", "1"):
        return True, False
    if oneway in ("-1", "reverse"):
        return False, True
    if oneway == "no":
        return True, True
    if tags.get("junction") in ("roundabout", "circular") or tags.get("highway") == "motorway":
        return True, False
    return True, True


class Collector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = []
        self.boundary = None

    def way(self, w):
        tags = w.tags
        if not car_allowed(tags):
            return
        coords = []
        inside = False
        south, west, north, east = PREFILTER
        for n in w.nodes:
            if not n.location.valid():
                return
            lat, lon = n.location.lat, n.location.lon
            inside = inside or (south <= lat <= north and west <= lon <= east)
            coords.append((n.ref, lat, lon))
        if inside and len(coords) >= 2:
            self.ways.append((coords, direction(tags), ROAD_CLASS[tags["highway"]]))

    def area(self, a):
        tags = a.tags
        if (a.from_way() or tags.get("boundary") != "administrative"
                or tags.get("admin_level") != "8" or tags.get("name") != "Petrolina"):
            return
        self.boundary = {
            "osm_relation": a.orig_id(),
            "name": tags.get("name"),
            "outer_rings": [[(round(n.lat, 6), round(n.lon, 6)) for n in ring] for ring in a.outer_rings()],
        }


def ring_bbox(rings):
    lats = [p[0] for r in rings for p in r]
    lons = [p[1] for r in rings for p in r]
    return min(lats), min(lons), max(lats), max(lons)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf")
    parser.add_argument("--versao", help="versão do pacote; padrão: data do extrato + .1")
    parser.add_argument("--margem-km", type=float, default=5.0)
    args = parser.parse_args()
    pbf = Path(args.pbf)

    header = osmium.io.Reader(str(pbf), osmium.osm.osm_entity_bits.NOTHING).header()
    osm_timestamp = header.get("osmosis_replication_timestamp") or header.get("timestamp") or ""
    reader_version = args.versao or f"{(osm_timestamp or dt.date.today().isoformat())[:10]}.1"

    collector = Collector()
    collector.apply_file(str(pbf), locations=True, idx="flex_mem")
    if not collector.boundary:
        sys.exit("limite municipal de Petrolina não encontrado no extrato")
    BOUNDARY_OUT.parent.mkdir(parents=True, exist_ok=True)
    BOUNDARY_OUT.write_text(json.dumps(collector.boundary) + "\n", encoding="utf-8")

    south, west, north, east = ring_bbox(collector.boundary["outer_rings"])
    margin_lat = args.margem_km / 111.0
    margin_lon = args.margem_km / (111.0 * math.cos(math.radians((south + north) / 2)))
    south, north = south - margin_lat, north + margin_lat
    west, east = west - margin_lon, east + margin_lon

    def inside(lat, lon):
        return south <= lat <= north and west <= lon <= east

    # Arestas dirigidas entre nós OSM, recortadas na cobertura.
    node_pos, edges = {}, []
    for coords, (fwd, bwd), cls in collector.ways:
        for (a, alat, alon), (b, blat, blon) in zip(coords, coords[1:]):
            if not (inside(alat, alon) and inside(blat, blon)):
                continue
            node_pos[a], node_pos[b] = (alat, alon), (blat, blon)
            length = haversine(alat, alon, blat, blon)
            if fwd:
                edges.append((a, b, length, cls))
            if bwd:
                edges.append((b, a, length, cls))

    # Mantém a maior componente fracamente conexa: ilhas geram "sem rota" enganoso.
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            parent[x] = parent.get(parent[x], parent[x])
            x = parent[x]
        return x

    for a, b, _, _ in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    sizes = {}
    for n in node_pos:
        r = find(n)
        sizes[r] = sizes.get(r, 0) + 1
    main_root = max(sizes, key=sizes.get)
    kept = sorted(n for n in node_pos if find(n) == main_root)
    dropped = len(node_pos) - len(kept)
    index = {n: i for i, n in enumerate(kept)}
    edges = [(index[a], index[b], l, c) for a, b, l, c in edges if a in index and b in index]
    edges.sort()
    # Remove arestas duplicadas (vias sobrepostas), mantendo a mais curta.
    unique = {}
    for a, b, l, c in edges:
        key = (a, b)
        if key not in unique or l < unique[key][0]:
            unique[key] = (l, c)
    edges = sorted((a, b, l, c) for (a, b), (l, c) in unique.items())

    n, m = len(kept), len(edges)
    lat = array("i", (round(node_pos[k][0] * 1e7) for k in kept))
    lon = array("i", (round(node_pos[k][1] * 1e7) for k in kept))
    offsets = array("I", [0] * (n + 1))
    for a, _, _, _ in edges:
        offsets[a + 1] += 1
    for i in range(n):
        offsets[i + 1] += offsets[i]
    target = array("I", (b for _, b, _, _ in edges))
    length = array("f", (l for _, _, l, _ in edges))
    classes = bytes(c for _, _, _, c in edges)
    for arr in (lat, lon, offsets, target, length):
        if sys.byteorder != "little":
            arr.byteswap()

    bbox_e7 = [round(v * 1e7) for v in (south, west, north, east)]
    payload = b"".join([
        b"OCRG", struct.pack("<III", FORMAT_VERSION, n, m), struct.pack("<4i", *bbox_e7),
        lat.tobytes(), lon.tobytes(), offsets.tobytes(), target.tobytes(), length.tobytes(), classes,
    ])
    ASSETS.mkdir(parents=True, exist_ok=True)
    compressed = gzip.compress(payload, compresslevel=9, mtime=0)
    (ASSETS / "petrolina-car.ocrg.gz").write_bytes(compressed)
    manifest = {
        "id": "petrolina-car",
        "format_version": FORMAT_VERSION,
        "version": reader_version,
        "region": "Petrolina–PE",
        "profile": "car",
        "bbox": {"south": south, "west": west, "north": north, "east": east},
        "margin_km": args.margem_km,
        "nodes": n,
        "edges": m,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "compressed_bytes": len(compressed),
        "compressed_sha256": hashlib.sha256(compressed).hexdigest(),
        "source": f"OpenStreetMap via Geofabrik ({pbf.name})",
        "osm_timestamp": osm_timestamp,
        "license": "ODbL 1.0 — © colaboradores do OpenStreetMap",
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "dropped_disconnected_nodes": dropped,
        "min_app_version": "0.1.0",
    }
    (ASSETS / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ("version", "nodes", "edges", "bytes", "compressed_bytes", "dropped_disconnected_nodes")}))


if __name__ == "__main__":
    main()
