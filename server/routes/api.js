/**
 * Routes for Minimal Signage's Fastify server
 * @param {FastifyInstance} fastify
 * @param {Object} options
 */

async function routes(fastify, options) {
    fastify.get('/', (req, res) => {
        res.send({ hello: 'world' })
    })
}

export default routes