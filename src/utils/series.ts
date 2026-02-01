import type { CollectionEntry } from "astro:content";

type Entry = CollectionEntry<"posts"> | CollectionEntry<"notes">;

/**
 * Extract order from filename (e.g., "kerberos-001-xxx.md" -> 1).
 * Uses the filePath property from Astro's content collection.
 */
export function getSeriesOrder(entry: Entry): number {
  // filePath is like "src/content/posts/kerberos-001-freeipa-deployment.md"
  const filePath = (entry as any).filePath as string | undefined;
  if (!filePath) return 0;

  const filename = filePath.split('/').pop() ?? '';
  const match = filename.match(/-(\d{3})-/);
  return match ? parseInt(match[1], 10) : 0;
}

/**
 * Get series information for display on cards.
 * Returns the series name, current part number, and total parts.
 */
export function getSeriesInfo(
  entries: Entry[],
  currentEntry: Entry
): { name: string; part: number; total: number } | null {
  const series = currentEntry.data.series;
  if (!series) return null;

  const seriesEntries = entries
    .filter((e) => e.data.series === series)
    .sort((a, b) => getSeriesOrder(a) - getSeriesOrder(b));

  const index = seriesEntries.findIndex((e) => e.id === currentEntry.id);
  if (index === -1) return null;

  return {
    name: series,
    part: index + 1,
    total: seriesEntries.length,
  };
}

/**
 * Get prev/next entries respecting series grouping.
 * Within a series: navigate by numeric ID (ascending order).
 * Without series: navigate by date (newest first).
 */
export function getSeriesNavigation(
  entries: Entry[],
  currentEntry: Entry
): { prev: Entry | null; next: Entry | null } {
  const series = currentEntry.data.series;

  if (!series) {
    // No series: use date-based navigation across all entries
    const sorted = [...entries].sort(
      (a, b) => b.data.date.getTime() - a.data.date.getTime()
    );
    const index = sorted.findIndex((e) => e.id === currentEntry.id);
    return {
      prev: index < sorted.length - 1 ? sorted[index + 1] : null,
      next: index > 0 ? sorted[index - 1] : null,
    };
  }

  // Has series: navigate within series only, ordered by numeric ID
  const seriesEntries = entries
    .filter((e) => e.data.series === series)
    .sort((a, b) => getSeriesOrder(a) - getSeriesOrder(b));

  const index = seriesEntries.findIndex((e) => e.id === currentEntry.id);
  return {
    prev: index > 0 ? seriesEntries[index - 1] : null,
    next: index < seriesEntries.length - 1 ? seriesEntries[index + 1] : null,
  };
}
