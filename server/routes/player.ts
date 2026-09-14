import { registerPlayerClient } from "../signage/broadcaster.js";
import { getScheduleUpdate } from "../signage/get-schedule.js";
import type { FastifyInstance } from 'fastify'

export async function playerRoutes(fastify: FastifyInstance, options: {}) {
    fastify.get("/", async (request, response) => {
        const playlist = await getScheduleUpdate()
        return response.viewAsync("layouts/player.hbs", {playlist, layout: "layouts/player.hbs"})
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