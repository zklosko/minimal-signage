import Fastify from "fastify"
import { apiRoutes } from "./routes/api.js"
import fastifyStatic from "@fastify/static"
import fastifyView from "@fastify/view"
import Handlebars from "handlebars"
import path from "node:path"
import { loadPartials } from "./views/load-partials.js"
import { playerRoutes } from "./routes/player.js"
import { adminRoutes } from "./routes/admin.js"
import { recomputeAndBroadcast } from "./signage/broadcaster.js"

const __dirname = import.meta.dirname
const fastify = Fastify({ logger: true })

await loadPartials(path.join(__dirname, "views/partials"))

fastify.register(fastifyStatic, {
    root: path.join(__dirname, 'public'),
    prefix: '/',
    constraints: {}
})

fastify.register(fastifyView, {
    engine: {
        handlebars: Handlebars
    },
    root: path.join(__dirname, 'views')
})

fastify.register(apiRoutes, {prefix: '/api'})
fastify.register(playerRoutes, {prefix: '/player'})
fastify.register(adminRoutes, {prefix: '/'})

fastify.listen({ port: 3000}, (err, address) => {
    if (err) {
        fastify.log.error(err)
        process.exit(1)
    }
    recomputeAndBroadcast()
    console.log('[server] Fastify listening on port 3000')
})