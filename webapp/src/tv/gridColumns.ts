// Splits a flat item list into rows of `n` — shared by every page that
// renders a uniform poster grid (GridPage/SearchPage/WatchlistPage) so the
// D-pad focus-engine's row/col addressing always matches whatever column
// count useGridColumns() currently reports, instead of three independent
// copies of the same function that could each drift.
export function chunk<T>(arr: T[], n: number): T[][] {
  const rows: T[][] = []
  for (let i = 0; i < arr.length; i += n) rows.push(arr.slice(i, i + n))
  return rows
}
