import { getCurrentAndNextItem } from "./get-schedule.js";

const clients = new Set()
let sequence = 0
let pendingTimer = null
let lastEvent = null

export function registerPlayerClient(reply) {
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