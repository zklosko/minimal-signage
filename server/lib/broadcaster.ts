import { getCurrentAndNextItem } from "./get-schedule.js";3

interface ScheduleItem {
    kind: string,
    id: string,
    message: string
}

interface LastEvent {
    sequence: number;
    serverTime: number;
    current: ScheduleItem | undefined;
    next: ScheduleItem | undefined;
}

const clients = new Set<any>()
let sequence = 0
let pendingTimer: NodeJS.Timeout | null = null
let lastEvent: LastEvent | null = null

export function registerPlayerClient(reply: any) {
    clients.add(reply)
    reply.raw.on("close", () => clients.delete(reply))
    reply.raw.on("error", () => clients.delete(reply))

    // Reconnecting client gets whatever was last sent
    if (lastEvent) {
        reply.raw.write(`event: item\ndata: ${JSON.stringify(lastEvent)}\n\n`)
    }
}

export async function recomputeAndBroadcast() {
    if (pendingTimer) clearTimeout(pendingTimer)
    
    const { current, next, msUntilNext } = await getCurrentAndNextItem()

    lastEvent = { sequence: ++sequence, serverTime: Date.now(), current, next}

    const payload = `event: item\ndata: ${JSON.stringify(lastEvent)}\n\n`

    for (const client of clients) {
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