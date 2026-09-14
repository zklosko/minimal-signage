import type { FastifyInstance } from 'fastify'
import { getScheduleUpdate } from '../signage/get-schedule.js'

export async function adminRoutes(fastify: FastifyInstance, options: {}) {
    fastify.get("/", async (request, response) => {
        const playlist = await getScheduleUpdate()
        return response.viewAsync('admin/dashboard.hbs', {
            playlist: playlist
        })
    })
}
