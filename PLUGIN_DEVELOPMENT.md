# PolyPals plugin development

PolyPals 0.4 accepts declarative `.polypals-pack` directories. It never executes plugin scripts or dynamic libraries. A pack contains `manifest.json`, payload under `content/`, `assets/`, or `localizations/`, plus `LICENSE` and `README.md`.

Copy `Examples/ContentPack` or `Examples/PetPack`, choose a stable reverse-domain ID, use semantic versions, declare the minimum app version, author, license, language, CEFR levels, capabilities, and a lowercase SHA-256 digest for every payload file. Paths must be relative and stay inside the pack.

Content cards support all seven built-in types and must declare minimum, recommended, and maximum CEFR levels. Culture cards need a verifiable source. Dialogue must be original or licensed. Pet packs require a unique non-built-in ID and Sprite v2: 192×208 cells, 8×11, 1536×2288, transparency, 11 animation rows, and 16 look directions.

Validate locally:

```sh
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
```

Installation, enable/disable, update, and deletion are offline. The app copies a pack to Application Support only after validation. Removed content packs preserve favorited card snapshots.
