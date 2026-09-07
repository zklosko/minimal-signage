import { registerPlayerClient } from "../lib/broadcaster.js";
import { getCurrentAndNextItem } from "../lib/get-schedule.js";

export async function playerRoutes(fastify) {
    fastify.get("/", async (req, res) => {
        playlist = getCurrentAndNextItem()
        return res.viewAsync("player.hbs", {playlist})
    })

    fastify.get("/events", async (req, res) => {
        res.raw.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        })

        // Prevent Fastify from waiting for response
        res.hijack()

        registerPlayerClient(res)
    })
}