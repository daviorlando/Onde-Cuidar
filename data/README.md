# Dados do Onde Cuidar

| Caminho | Conteúdo | Versionado |
| --- | --- | --- |
| `raw/cnes-261110.json` | Resposta bruta da API de dados abertos do CNES (Petrolina) | Sim |
| `raw/petrolina-limite.json` | Limite municipal extraído do OSM (relação 303629) | Sim |
| `raw/osm/` | Extrato Geofabrik (~440 MB) | Não |
| `inventory/inventario-cnes-petrolina.csv` | Inventário candidato: todos os registros, com decisão e motivo | Sim |
| `catalog/catalog.json` | Catálogo publicado (esquema v1); cópia idêntica em `app/assets/catalog/` | Sim |

Todos os registros estão com `review_status: pending`: vieram do cadastro e ainda não foram conferidos pela curadoria. A curadoria altera o inventário e o catálogo por PR, registrando fonte e data de cada confirmação, e muda o registro para `approved` só depois de conferir.

## Regenerar

```bash
python3 scripts/data/fetch_cnes.py                     # atualiza data/raw/cnes-261110.json
curl -LO --output-dir data/raw/osm https://download.geofabrik.de/south-america/brazil/nordeste-latest.osm.pbf
python3 -m pip install osmium                           # em ambiente virtual
python3 scripts/data/build_road_graph.py data/raw/osm/nordeste-latest.osm.pbf   # pacote + limite
python3 scripts/data/build_catalog.py                   # inventário + catálogo
cp data/catalog/catalog.json app/assets/catalog/catalog.json
python3 scripts/data/validate_data.py
```

A versão do catálogo (`AAAA-MM-DD.N`) precisa crescer a cada publicação; o app recusa versão anterior. Licenças: CNES, dado público do Ministério da Saúde; vias, © colaboradores do OpenStreetMap (ODbL 1.0), com atribuição exibida no app.
