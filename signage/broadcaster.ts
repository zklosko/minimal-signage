import { getScheduleUpdate } from "./get-schedule.js";

interface ScheduleItem {
    id: string;
    type: "image" | "video" | "webpage" | "empty";
    src: string;
    message?: string;
}

type ScheduleUpdate = Awaited<ReturnType<typeof getScheduleUpdate>>

interface LastEvent {
    sequence: number;
    serverTime: number;
    current: ScheduleUpdate["current"];
    next: ScheduleUpdate["next"];
}

interface PlayerClient {
    raw: {
        write(data: string): boolean
        on(event: "close" | "error", listener: () => void): void
    }
}

const clients = new Set<PlayerClient>()
let sequence = 0
let pendingTimer: NodeJS.Timeout | null = null
let lastEvent: LastEvent | null = null

export function registerPlayerClient(reply: any) {
    clients.add(reply)
    reply.raw.on("close", () => clients.delete(reply))
    reply.raw.on("error", () => clients.delete(reply))

    // Reconnecting client gets whatever was last sent
    if (lastEvent) {
        console.log("[broadcaster] lastEvent:", lastEvent) // TESTING
        reply.raw.write(`event: item\ndata: ${JSON.stringify(lastEvent)}\n\n`)
    }
}

export async function recomputeAndBroadcast() {
    console.log("[broadcaster] recomputing")  // TESTING
    if (pendingTimer) clearTimeout(pendingTimer)
    
    const { current, next, msUntilNext } = await getScheduleUpdate()

    lastEvent = { sequence: ++sequence, serverTime: Date.now(), current, next}

    console.log("[broadcaster] update", {
        current,
        next,
        msUntilNext,
    }) // TESTING

    const payload = `event: item\ndata: ${JSON.stringify(lastEvent)}\n\n`

    for (const client of clients) {
        console.log("[broadcaster] sending to client")  // TESTING
        client.raw.write(payload)
    }

    // Server schedules its next transition
    if (msUntilNext != null) {
        pendingTimer = setTimeout(recomputeAndBroadcast, msUntilNext)
    }
}

setInterval(() => {
    for (const c of clients) c.raw.write(": keep-alive\n\n")
}, 20_000)