# Claude Code Status Bar

Rozbudowany dwuliniowy pasek stanu dla [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (CLI). Wyświetla model, zużycie kontekstu, realne limity planu Pro/Max (5h / 7d / 7d Opus), dane systemowe i pogodę.

## Podgląd

```
Opus 4.7 │ 🧩 CTX: ▮▮▯▯▯▯▯▯▯▯ 18% │ 💎 ▮▯▯▯▯▯▯▯▯▯ 7% (55m) │ 📆 7d: 12% (4d12h)
🕐 07:04 │ 📁 ~/D/P/Projekt │ 💾 142GB │ 🧠 8.2GB │ ⚙ 23% │ ⚡ 87%                 ☀ 18°C
```

## Co wyświetla

### Linia 1 — AI i limity planu
| Element | Opis |
|---------|------|
| **Model** | Nazwa aktywnego modelu (np. `Opus 4.7`, `Sonnet 4.6`) |
| **🧩 CTX** | Zużycie okna kontekstowego sesji (z paskiem i %) |
| **💎** | Zużycie limitu w bieżącym oknie **5h** + czas do resetu |
| **📆 7d** | Zużycie tygodniowego limitu planu + czas do resetu |
| **🧠 Opus** | Osobny 7-dniowy licznik Opusa (Max plan; ukryty przy 0%) |

### Linia 2 — Środowisko
| Element | Opis |
|---------|------|
| **🕐 Zegar** | Aktualna godzina |
| **📁 Katalog** | Skrócona ścieżka robocza |
| **💾 Dysk** | Wolne miejsce |
| **🧠 RAM** | Wolna pamięć |
| **⚙ CPU** | Obciążenie procesora |
| **🔋/⚡ Bateria** | Poziom + tryb (bateria/AC) |
| **Pogoda** | Temperatura i ikona (prawa strona) |

## Kolorowanie

Wartości procentowe zmieniają kolor wg poziomu:
- **Zielony** — poniżej 50%
- **Żółty** — 50-74%
- **Pomarańczowy** — 75-89%
- **Czerwony** — 90%+

## Skąd dane o limitach?

Claude Code 2.x trzyma limity planu **po stronie serwera Anthropic**. Stare skrypty używające `ccusage blocks` pokazywały `100% z 0` bo lokalne pliki JSONL nie mają pełnego obrazu.

Ten skrypt używa tego samego endpointa co Claude Code dla `/status`:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken z Keychain>
anthropic-beta: oauth-2025-04-20
```

Token OAuth odczytywany jest z macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`). Wyniki są cache'owane 5 min.

Jeśli Keychain lub endpoint są niedostępne, sekcje 5h/7d chowają się automatycznie — reszta paska działa normalnie.

## Wymagania

- **macOS** (używa `top`, `vm_stat`, `pmset`, `df`, `security`)
- **jq** — parsowanie JSON
- **curl** — wywołanie OAuth endpointa + pogoda
- Zalogowany Claude Code z planem Pro/Max (dla sekcji 5h/7d)

## Instalacja

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Dodaj do `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/TWOJA_NAZWA/.claude/statusline.sh"
  }
}
```

Aby uniknąć promptów permission przy każdym odświeżeniu, dopisz w `permissions.allow`:

```json
"Bash(security find-generic-password:*)",
"Bash(curl * api.anthropic.com/api/oauth/usage*)"
```

Restart Claude Code — pasek pojawi się na dole terminala.

## Konfiguracja

Na górze skryptu:

```bash
CC_USAGE_ENDPOINT="https://api.anthropic.com/api/oauth/usage"
CC_KEYCHAIN_SERVICE="Claude Code-credentials"
CC_USER_AGENT="claude-code/2.0.32"
```

## Cache

| Dane | Cache | Plik |
|------|-------|------|
| Limity planu (OAuth) | 5 min | `/tmp/.cc_usage_limits` |
| CPU | 60s | `/tmp/.cc_cpu_cache` |
| RAM | 60s | `/tmp/.cc_ram_cache` |
| Dysk | 10 min | `/tmp/.cc_disk_cache` |
| Bateria | 60s | `/tmp/.cc_bat_cache` |
| Pogoda | 10 min | `/tmp/.cc_weather` |

## Jak działa

1. Claude Code wywołuje skrypt co kilka sekund, przekazując JSON sesji na stdin.
2. Skrypt odczytuje z JSON: model, `context_window.remaining_percentage` (z fallbackiem na stary format).
3. Pobiera token OAuth z Keychain i pyta endpoint `api/oauth/usage` o realne limity 5h/7d/Opus.
4. Zbiera dane systemowe (CPU, RAM, dysk, bateria) z narzędzi macOS.
5. Pobiera pogodę z Open-Meteo API na podstawie lokalizacji IP.
6. Formatuje wszystko w dwie kolorowe linie z paskami graficznymi i wyrównaniem lewo/prawo.

## Inspiracja / źródła

- [codelynx.dev — Claude Code Usage Limits Statusline](https://codelynx.dev/posts/claude-code-usage-limits-statusline)
- Issues: [#15366](https://github.com/anthropics/claude-code/issues/15366), [#12520](https://github.com/anthropics/claude-code/issues/12520), [#15931](https://github.com/anthropics/claude-code/issues/15931)

## Licencja

MIT
