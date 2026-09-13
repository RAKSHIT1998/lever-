Real-world parsing corpus. Drop each document's recognised text here as `<name>.txt`, optionally with a
`<name>.expected.json` next to it:

{ "merchant": "Croma", "amount": 26990, "purchaseDate": "2026-09-10", "documentType": "invoice" }

`RealCorpusTests` replays every file through the on-device parser and reports misses.
Files here may contain personal data — keep this folder out of public forks if needed.
