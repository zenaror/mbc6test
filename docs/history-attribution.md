# Commit attribution maintenance (2026-10-12)

Eight automatic Claude/Anthropic `Co-authored-by` trailers were removed from
this project's commit messages. The affected root and its descendants give
all 25 existing commits new hashes. Authors, committers, dates, file trees,
human credits and other message content are preserved. A separate documentation
commit adds the AI assistance note, the agent instruction and this map.

Only `main` and the two lightweight release tags are updated. Their historical
names are retained with equivalent targets:

| Tag | Rewritten target |
|---|---|
| `70e44e9` | `c93a891862836c20a13948e0786e135e039bf68b` |
| `82b9704` | `6c20fd1d5baaf839c6a48fb132204611701d0b87` |

No signed commits or annotated tags occur in this scope. ROMs, distributed
binaries and validation manifests were not rebuilt or modified by this change.
The mGBA commit identifiers refer to a separate repository and are not covered
by this map.

## Evidence and historical identifiers

Dated findings and build manifests retain their original hashes as provenance.
For example, frozen TestROM source `b7c905b45fee1624e2e749e3477f8829a7fa5e49`
now corresponds to the entry below with the same file tree. An old commit URL
may stop resolving after remote cleanup; use this map to locate the equivalent
source. The old build identifiers printed by ROMs still identify those original
builds. Recoverable original history is retained locally by the maintainer;
backup refs, bundles, stashes and internal data are not published.

## Existing clones

A fresh clone is the simplest way to obtain the updated history. Before changing
an existing clone, save uncommitted work and local branches in a separate backup.
Fetch the updated `main`; updating the moved tags requires explicit forced
fetches of those tags. Do not merge or push the old `main` into the rewritten branch.
Use the map to find the equivalent base and replay only unpublished local work.
Other repositories that pin these commits or the tag must update their pins
deliberately. Only the maintained GitHub repository is covered; external mirrors
and downstream submodule pins are not automatically updated.

## Old to rewritten commit map

These are equivalents of existing commits, excluding the new documentation
commit. `Trailer removed` identifies the eight edited messages; all remaining
hash changes result from changed parent hashes.

| Original commit | Rewritten commit | Trailer removed |
|---|---|---|
| `95ecd80445ea44b52d00c9f49b4513f07d1cce18` | `9d13744889abbfe63841b270f720819d6fb715c3` | yes |
| `f8de7509a95426a993d42334ca9dd5c1a8e099b0` | `c8691095a52e9fc25ac4b57c5398c878533610e1` | yes |
| `a08521a1e819452b7050d3b9e2755317455f0b78` | `34da1ae5d37f3dc8b19b364fed9e977e797b878b` | yes |
| `3298a73608f1e14c43d062e281363b6c5eaa0e9b` | `b42d09a06c0f7f7e1e81caacb2278de85dfeb687` | yes |
| `d151752b8c1632b2e756959ab2444488209ecfcf` | `04878aaf27b3fb08d4e07a336fa6e9f7be413b24` | no |
| `466ac0856300439a68ee9de5a69b5233109065ec` | `bb5b9b6c4d23ea992928c25553bc972103db039b` | yes |
| `f9d05b23298afd0706673a48a228f9d089187be6` | `79efb03a7f2f63cfba59515d6d97665d95e65a92` | yes |
| `8d586f9716684494e165bb4d15cde124203ed82d` | `03eed827b0daf718be482a57279f5541f403a1d5` | yes |
| `57f6c3544b1d142281d15b3f168f3275adce84fb` | `1516d2b090fcbc62028fe0fda36fbc97d32abd00` | yes |
| `ad9f9834987f0604f36fc45b8439e4b3f2134cc0` | `31bda2ea477661cb7aea7f947c2f54e1284d4fab` | no |
| `045b4d34947d26d4f1ccdcc9b50e154055ff5ca5` | `939871c50b40ea44ac132a3697eb5b4776fbe3d9` | no |
| `411ba0b0b5c3ccba5e1ce4639c2ab0123a0fb29f` | `734d1256ba49dff6a2bcf7a1f0e018e5fb6509af` | no |
| `25c86275855098dfa11d7d77c8f0b53550a800d0` | `6ea9d4fc08430b891dca7c01d5cee274417807f1` | no |
| `70e44e9da9a25a846df1f6badbb4ebbdde12880b` | `c93a891862836c20a13948e0786e135e039bf68b` | no |
| `1a1ae522db6b83ab917ac2b48df9fbb4e4b5ec4d` | `3f1fabea9ec8139ea28af66f9960b151e6357da8` | no |
| `1e4400054c603c43f653f00a419152362a922b97` | `d6d6fc1af5c3a5eb1598a6fa9e3e53ad7a0eea65` | no |
| `b7c905b45fee1624e2e749e3477f8829a7fa5e49` | `20950391e93cb7eb482f4c60fbaead5ec081a000` | no |
| `b3297946e6d0bb9d32c754f1eedbb3d5e83eaa0b` | `28d48607c7d5447c9ea7269abde4f760aec92253` | no |
| `82b9704561aea53db864f22e0382292f567cb164` | `6c20fd1d5baaf839c6a48fb132204611701d0b87` | no |
| `9bb125a359a0a5ad454ab155adb97fd3bd22cfbe` | `993abc2f67366171ce520b7b4f792e7ee19f5cb8` | no |
| `673fccea3c67750d3c813cab0f2f55e5873733c9` | `eca9cc4f692a9ea8d80937eac14786c4ac25bb58` | no |
| `1dc9953fa805dcee53e0764880c890ed69cd087d` | `f85dd0d49c8dfd833754df5cbb7ef937e4842475` | no |
| `acc3152677f84958fe287cd9abd001e7c5be3a78` | `6a8b6aa7db148f691f9880451495ec3057e32f79` | no |
| `142c4c3ced904162a072b2e9ba9a1fb989dd5fe6` | `991d9c861709f807eb074f13b87a637c9f55e8b3` | no |
| `85512dedae174550d106dabfa09866de4f653008` | `dd191f7a3223cbfd25869fe9f43c061edea73173` | no |
