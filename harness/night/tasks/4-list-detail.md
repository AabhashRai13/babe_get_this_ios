# Task 4: List detail screen
Branch `night/4-list-detail`. Simulator `bgt-night-4`.

## Owned paths
- `BabeGetThis/Features/ListDetail/`
- `BabeGetThisTests/ListDetail/`
- `docs/night/screens/`
- `docs/night/4-list-detail.md`

## Port from (Android, `origin/feat/got-this`)
`ShoppingItemsScreen`, its components and `ShoppingItemsViewModel` (`feature/shoppingitems/ui/`), and the screenshot
`docs/screenshots/02-sunday-roast.png` in the Android folder (read it with the Read tool). Use the existing design system
(`BabeGetThis/Core/DesignSystem/`) and `ShoppingListSummary` (read only).

## Acceptance (immutable)
- Replaces `ListDetailPlaceholderView` (same type name and same `init(list: ShoppingListSummary)`, so `ListsView` is unchanged).
- Progress card ("3 of 7 picked up", percentage, bar). ACTIVE ITEMS grouped by shop, then category. COMPLETED section below.
- Item card: tick circle, name, italic note, quantity and category chips in the brand colours.
- Tick/untick moves an item between Active and Completed. Swipe to delete with an Undo snackbar.
- Add-item sheet: name (required), quantity (required), category picker, shop, note.
- An in-memory `@Observable` view model with unit tests for grouping, progress, tick, delete/undo and add validation
  (at least 5 `func test` in `BabeGetThisTests/ListDetail/`).
- Uses `AppColors` and `AppMetrics` only (no hex values in views).
- **Fixed sample data (reliability amendment R6):** when `list.id == "sample-sunday-roast"`, the screen shows exactly these items:
  active: Red wine (1 bottle, Beer, Wine & Spirits, shop Dan Murphys, note "Something that goes with lamb");
  Lamb leg (2.5 kg, Meat & Seafood, The Butcher Block, "Bone in - ask for the shank end");
  Double cream (300 ml, Dairy & Eggs, Woolworths, "For the gratin");
  Baby potatoes (1.5 kg, Fruits & Vegetables, Woolworths, "The waxy ones, not floury");
  completed: Sourdough (1 loaf, Bakery & Bread, Woolworths, "Get there before 10 or it is gone").
  Other lists start empty.
- Light and dark screenshots: after a passing `./scripts/verify.sh bgt-night-4`, run `./scripts/screenshots.sh bgt-night-4`.
  It writes `docs/night/screens/list-detail-light.png` and `list-detail-dark.png` using the route `-sampleData -openList sample-sunday-roast`.
  Look at both with the Read tool and fix layout problems before committing them.
- `./scripts/verify.sh bgt-night-4` passes.
