import type { FastifyInstance } from 'fastify'

export async function adminRoutes(fastify: FastifyInstance, options: {}) {
    fastify.get("/", async (request, response) => {
        return response.viewAsync('admin/dashboard.hbs', {
            title: 'Dashboard',
            heading: 'Dashboard'
        })
    })
}
