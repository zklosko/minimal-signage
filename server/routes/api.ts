import type { FastifyInstance } from 'fastify'

export async function apiRoutes(fastify: FastifyInstance, options: {}) {
    fastify.get('/', (request, response) => {
        response.send({ hello: 'world' })
    })
}
