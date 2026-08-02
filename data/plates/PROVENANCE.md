# Bundled plates dataset (PRD-PLATES, full corpus)

Copy of `plates/` from the public data repo (EXCLUDING `_art/`),
refreshed on gem releases:

- **Source**: https://github.com/vehiclesdb/vehiclesdb `plates/`
- **Commit**: `90bd588f1667716402c168ba1f3b5a049128f692`
- **License**: CC-BY 4.0 (see the data repo's LICENSE + ATTRIBUTION.md)

Refresh: run `rake plates:refresh` (recreates this file — it is
GEM-LOCAL and a bare `rm -rf data/plates && git archive` EATS it;
that failure shipped once in 0.7.4).
