# Bundled plates dataset (PRD-PLATES, full corpus)

Copy of `plates/` from the public data repo (EXCLUDING `_art/` — the
asset tier stays in the data repo; this gem bundles the format data),
refreshed on gem releases:

- **Source**: https://github.com/vehiclesdb/vehiclesdb `plates/`
- **Commit**: `8b41cb76315a48909562acdaeef654d994ab83cc`
- **License**: CC-BY 4.0 (see the data repo's LICENSE + ATTRIBUTION.md)

Refresh: `git archive origin/main plates | tar -x --exclude 'plates/_art' -C data/`
then update the commit line.
