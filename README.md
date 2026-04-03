# Claude Code Status Bar

Rozbudowany dwuliniowy pasek stanu dla [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (CLI). Wyswietla informacje o modelu AI, zuzyciu kontekstu, limitach tokenow, systemie i pogodzie.

## Podglad

```
Opus 4.6 (1M) │ 🧩 CTX: ▮▮▮▯▯▯▯▯▯▯ 28% │ 💎 TOKENY: ▮▮▯▯▯▯▯▯▯▯  4.2M/10.8M 28% │ koniec ~3h12m │ reset 1h47m
🕐 14:32 │ 📁 ~/D/P/S/MojProjekt │ 💾 142GB │ 🧠 8.2GB │ ⚙ 23% │ ⚡ 87%                                    ☀ 18°C
```

## Co wyswietla

### Linia 1 — AI i tokeny
| Element | Opis |
|---------|------|
| **Model** | Nazwa aktywnego modelu (np. `Opus 4.6 (1M)`) |
| **CTX** | Zuzycie okna kontekstowego z paskiem graficznym i % |
| **TOKENY** | Zuzycie limitu 5h z ccusage — zuzyte/pozostale + % |
| **koniec** | Szacowany czas do wyczerpania tokenow (na podstawie tempa) |
| **reset** | Czas do resetu bloku 5h |

### Linia 2 — Srodowisko
| Element | Opis |
|---------|------|
| **Zegar** | Aktualna godzina |
| **Katalog** | Skrocona sciezka robocza |
| **Dysk** | Wolne miejsce na dysku |
| **RAM** | Wolna pamiec operacyjna |
| **CPU** | Obciazenie procesora |
| **Bateria** | Poziom baterii (ikona zmienia sie: akumulator/ladowanie) |
| **Pogoda** | Aktualna temperatura i ikona pogody (prawa strona) |

## Kolorowanie

Wszystkie wartosci procentowe (CTX, TOKENY, CPU, bateria) zmieniaja kolor w zaleznosci od poziomu:
- **Zielony** — ponizej 50%
- **Zolty** — 50-74%
- **Pomaranczowy** — 75-89%
- **Czerwony** — 90%+

## Wymagania

- **macOS** (uzywa `top`, `vm_stat`, `pmset`, `df` specyficznych dla macOS)
- **jq** — parsowanie JSON
- **[ccusage](https://github.com/ryoppippi/ccusage)** — dane o zuzyciu tokenow (opcjonalne, bez niego sekcja TOKENY pokazuje 0)
- **curl** — pobieranie pogody (opcjonalne)

## Instalacja

1. Skopiuj `statusline.sh` do `~/.claude/`:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Dodaj do `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/sciezka/do/.claude/statusline.sh"
  }
}
```

3. Uruchom ponownie Claude Code — pasek pojawi sie na dole terminala.

## Konfiguracja

Na gorze skryptu mozesz zmienic limit tokenow:

```bash
BLOCK_LIMIT_5H=15000000   # Domyslnie 15M tokenow na blok 5h
```

## Cache

Dane systemowe sa cache'owane w `/tmp/` zeby nie spowalniaj wyswietlania:

| Dane | Cache | Plik |
|------|-------|------|
| ccusage (tokeny) | 5 min | `/tmp/.cc_usage_cache` |
| CPU | 60s | `/tmp/.cc_cpu_cache` |
| RAM | 60s | `/tmp/.cc_ram_cache` |
| Dysk | 10 min | `/tmp/.cc_disk_cache` |
| Bateria | 60s | `/tmp/.cc_bat_cache` |
| Pogoda | 10 min | `/tmp/.cc_weather` |

## Jak dziala

1. Claude Code wywoluje skrypt co kilka sekund, przekazujac dane sesji jako JSON na stdin
2. Skrypt odczytuje z JSON: nazwe modelu, zuzycie kontekstu, rozmiar okna kontekstowego
3. Wywoluje `ccusage blocks --json` aby pobrac dane o zuzyciu tokenow w biezacym bloku 5h
4. Zbiera dane systemowe (CPU, RAM, dysk, bateria) z narzedzi macOS
5. Pobiera pogode z Open-Meteo API na podstawie lokalizacji IP
6. Formatuje wszystko w dwie kolorowe linie z paskami graficznymi i wyrownaniem lewo/prawo

## Licencja

MIT
