# TallyTaps mobile

TallyTaps is an offline-first field recorder and quick-billing companion for non-technical users working in busy market environments.

## Quick recording

Cash, card, stock, and note entries are written to SQLite immediately. Images and audio upload before their owning record, and failed uploads remain locally retryable.

## Quick billing

After the phone is approved by a host and a connected DDEC POS publishes its catalog:

1. Tap **Create a quick bill**.
2. Choose the POS item list to use.
3. Search and tap products; weight, price-override, wage, bag, and other product snapshots are retained in the bill.
4. Choose paid by cash/card or unpaid.
5. Route the bill to the selected POS inbox or every connected POS.

Catalogs are cached, so billing can continue offline after the first download. A bill is saved locally before any network request; pending bills retry after connectivity returns. The bill is a standalone field sale and does not modify the POS sales, stock, cash, or customer ledgers. A receiving POS can print it with its own current shop receipt header and footer.
