import { registerPlayerClient } from "../lib/broadcaster.js";
import { getCurrentAndNextItem } from "../lib/get-schedule.js";
import type { FastifyInstance } from 'fastify'

export async function playerRoutes(fastify: FastifyInstance, options: {}) {
    fastify.get("/", async (request, response) => {
        const playlist = getCurrentAndNextItem()
        return response.viewAsync("player.hbs", {playlist})
    })

    fastify.get("/events", async (request, response) => {
        response.raw.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        })

        // Prevent Fastify from waiting for response
        response.hijack()

        registerPlayerClient(response)
    })
}