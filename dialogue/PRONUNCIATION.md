# Pronunciation Glossary

Phonetic respellings for proper nouns the TTS model will mispronounce. Use the **TTS spelling** column in `dialogue/scripts/*.txt` files. Keep canonical spellings in lore files only.

When adding a new proper noun, listen to the model attempt the canonical spelling first. If it lands cleanly, no entry is needed. If it doesn't, add a row.

Stress is marked with capital letters on the stressed syllable.

---

## Places

| Canonical | TTS spelling | Notes |
|---|---|---|
| Aldenholt | Aldenholt | Lands clean. No respelling. |
| Brightwatch | Brightwatch | Lands clean. |
| Coldstoke | Coldstoke | Lands clean. |
| Solgrade | SOL-grade | Hard "g". |
| Vosskara | voss-KAR-uh | |
| Caer Brannoch | kair BRAN-uck | "Caer" is one syllable, like "care". "Brannoch" Welsh-flavored. |
| Eldermark | Eldermark | Lands clean. |
| Khorumzad | KOR-um-zahd | Skip the "h". |
| Drûn-Khazad | droon kah-ZAHD | The û is "oo" as in "moon". |
| Karaz-Dûn | KAR-az doon | |
| Kazaad-Brak | kah-ZAHD brak | |
| Aescstól | ASK-stoll | The ó is long "o". Two syllables. |
| Aen-Vael | ane VALE | Two syllables. "Ane" rhymes with "lane". |
| Lirien-Thal | LEER-ee-en THAHL | |
| Sirathiel | sih-RATH-ee-el | |
| Aelorin Greatwood | AY-loh-rin Greatwood | |
| Vosskara | voss-KAR-uh | (repeat for ease of lookup) |
| Drûn-Khazad | droon kah-ZAHD | (repeat) |

## Peoples / Languages

| Canonical | TTS spelling | Notes |
|---|---|---|
| Aelorin | AY-loh-rin | The elven people. |
| Aeluvain | AY-loo-vain | The binding magic / artifact language. |
| Aescryd | ASK-rid | Second Age people. |
| Aelthuren / Aelthiren | ayl-THOO-ren / ayl-THEE-ren | Two distinct rituals — keep them straight. |
| Naergrim | NAIR-grim | |
| Caelborn | KAIL-born | One syllable for "cael". |
| Ashfallen | Ashfallen | Lands clean. |

## Characters — Protagonist & Companions

| Canonical | TTS spelling | Notes |
|---|---|---|
| Roland Ashford | Roland Ashford | Lands clean. |
| Corvus Tane | KOR-vus TAYN | |
| Seren | SEH-ren | Welsh "Seren". Not "Sair-en". |
| Orion Farr | oh-RYE-un FAR | |
| Dagna Irontrack | DAG-nuh Irontrack | |
| Bromrin Deepdelver | BROM-rin Deepdelver | |
| Aldric Vane | AL-drick VAYN | |

## Characters — NPCs

| Canonical | TTS spelling | Notes |
|---|---|---|
| Henrietta | hen-ree-ETT-uh | |
| Tomlin | TOM-lin | |
| Dame Calla Vane | dame KAL-uh VAYN | |
| Edran Vane | ED-ran VAYN | |
| Ser Aldric Vossant | sir AL-drick voh-SAHNT | Distinct from Aldric Vane. |
| Despot Yaromir | DESS-pot YAR-uh-meer | |
| Queen Eilwen | EYE-lwen | One syllable for "Eil". |
| Drossvik | DROSS-vik | |
| Ser Brenn | sir BREN | |
| Mira Halsten | MEER-uh HAHL-sten | |
| Aelthurion | ayl-THOO-ree-on | The ancient Vigil-Keeper. |

## Villains

| Canonical | TTS spelling | Notes |
|---|---|---|
| Mordvar | MORD-var | |
| Bealoric | BAY-oh-rick | Mordvar's original name. |
| Vaeroth the Pale | VAIR-oth | |
| Caerith | KAIR-ith | The Ashlord's true name. |
| Prince Aedric Castrove | AY-drick KAS-trove | |

## Houses & Orders

| Canonical | TTS spelling | Notes |
|---|---|---|
| House Korvath | KOR-vath | |
| House Pelarin | PEL-a-rin | |
| Iron Chalice | Iron Chalice | Lands clean. |
| Frost Brotherhood | Frost Brotherhood | Lands clean. |
| Golden Lance | Golden Lance | Lands clean. |
| Dawnbringers | Dawnbringers | Lands clean. |
| Crimson Ledger | Crimson Ledger | Lands clean. |
| Conclave of the Unseen Hand | Conclave of the Unseen Hand | Lands clean. |
| Ashen Hand | Ashen Hand | Lands clean. |
| Hollow Court | Hollow Court | Lands clean. |
| Tidewardens | Tidewardens | Lands clean. |
| Dragon-Watchers | Dragon-Watchers | Lands clean. |

## Dwarven gods (used in oaths)

| Canonical | TTS spelling | Notes |
|---|---|---|
| Kradir the Unmoving | KRAH-deer | |

---

## Workflow

When writing a script that uses a lore term:

1. Look it up here. If listed, use the **TTS spelling** column verbatim.
2. If not listed, generate one test line with the canonical spelling. If the model nails it, do nothing. If not, add an entry here and update the script.
3. Audit: when a new lore file lands in `lore/`, scan for new proper nouns and add stubs to this file before they hit a script.