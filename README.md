# Onde Cuidar

Aplicativo Flutter para Android que ajuda a encontrar unidades de saúde públicas e particulares em Petrolina–PE, consultar informações e calcular rotas mesmo sem internet, dentro da região instalada.

- Catálogo local em SQLite (Drift), embarcado no APK: busca, filtros e detalhes funcionam offline.
- Filtros por atendimento, natureza (pública ou privada), acesso SUS, 24 horas, especialidade e plano. Entre grupos vale **E**, dentro de um grupo vale **OU**, e informação desconhecida nunca passa por filtro.
- Ordenação por compatibilidade e depois pela distância pelas ruas. A distância é calculada no aparelho, por Dijkstra sobre um grafo do OpenStreetMap, para todas as unidades elegíveis.
- Origem pela localização (pedida só ao usar) ou por um ponto escolhido no mapa offline.
- Atualização opcional do catálogo por manifesto assinado (Ed25519), com verificação de hash e troca atômica.
- Sem conta, sem estatísticas de uso e sem envio da localização.

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `app/` | Aplicativo Flutter (`lib/app`, `lib/core`, `lib/features/{facilities,search,routing,offline,about}`), testes e testes de integração |
| `app/tool/` | Geração de chave e publicação assinada do catálogo |
| `scripts/data/` | Coleta no CNES, geração do catálogo, geração do pacote viário e validação |
| `data/` | Dados brutos do CNES, inventário candidato e catálogo publicado (ver [data/README.md](data/README.md)) |
| `.github/workflows/` | CI (`flutter-quality`, `data-checks`) e release manual assinado |

## Desenvolvimento

Requer Flutter 3.47.4 (ver `.flutter-version`) e um JDK de 17 a 25.

```bash
cd app
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs   # após mudar tabelas Drift
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter test integration_test -d <dispositivo>   # com a rede do aparelho desligada
```

Na raiz:

```bash
python3 scripts/check_docs.py          # links locais de Markdown
python3 scripts/data/validate_data.py  # catálogo e pacote viário embarcados
```

## Dados e licenças

- Unidades: [CNES — API de dados abertos do Ministério da Saúde](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos). Os registros vêm do cadastro e ainda não foram conferidos localmente; o app sinaliza isso.
- Vias e mapa: © colaboradores do [OpenStreetMap](https://www.openstreetmap.org/copyright), sob a licença ODbL 1.0, com atribuição exibida no app.

A licença do código ainda não foi definida.
