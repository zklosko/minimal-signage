export type PlayerItem =
    | { kind: "image"; id: string; url: string; durationMs: number}
    | { kind: "video"; id: string; url: string; durationMs: number}
    | { kind: "text"; id: string; content: string; durationMs: number; style: Record<string, string> }
    | { kind: "empty"; id: "empty"; message?: string}
    