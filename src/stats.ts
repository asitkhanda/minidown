export type StatsMode = "words" | "chars" | "time";

const MODES: StatsMode[] = ["words", "chars", "time"];
const WORDS_PER_MINUTE = 220;

export function nextStatsMode(mode: StatsMode): StatsMode {
  return MODES[(MODES.indexOf(mode) + 1) % MODES.length];
}

export function countWords(text: string): number {
  return text.match(/\S+/g)?.length ?? 0;
}

export function formatStats(text: string, mode: StatsMode): string {
  switch (mode) {
    case "words": {
      const words = countWords(text);
      return `${words.toLocaleString()} ${words === 1 ? "word" : "words"}`;
    }
    case "chars": {
      const chars = text.length;
      return `${chars.toLocaleString()} ${chars === 1 ? "character" : "characters"}`;
    }
    case "time": {
      const words = countWords(text);
      if (words === 0) return "0 min read";
      const minutes = Math.ceil(words / WORDS_PER_MINUTE);
      return `${minutes} min read`;
    }
  }
}
