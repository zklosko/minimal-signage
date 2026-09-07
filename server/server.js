import Fastify from "fastify"
import routes from "./routes/api.js"
import fastifyStatic from "@fastify/static"
import fastifyView from "@fastify/view"
import Handlebars from "handlebars"
import path from "node:path"
import { loadPartials } from "./views/load-partials.js"
import { playerRoutes } from "./routes/player.js"
import { recomputeAndBroadcast } from "./lib/broadcaster.js"

const __dirname = import.meta.dirname
const fastify = Fastify({ logger: true })

await loadPartials(path.join(__dirname, "views/partials"))

fastify.register(fastifyStatic, {
    root: path.join(__dirname, 'public'),
    prefix: '/',
    constraints: {}
})

fastify.register(routes, {prefix: '/api'})
fastify.register(playerRoutes, {prefix: '/player'})

fastify.register(fastifyView, {
    engine: {
        handlebars: Handlebars
    },
    root: path.join(__dirname, 'views'),
    layout: 'layouts/base.hbs'
})

fastify.get("/", async (req, res) => {
    return res.viewAsync('admin/dashboard.hbs', {
        title: 'Dashboard',
        heading: 'Dashboard'
    })
})
fastify.get("/media", async (req, res) => {
    return res.viewAsync('admin/media.hbs', {
        title: 'Media',
        heading: 'Media'
    })
})
fastify.get("/playlists", async (req, res) => {
    return res.viewAsync('admin/playlists.hbs', {
        title: 'Playlists',
        heading: 'Playlists'
    })
})
fastify.get("/schedule", async (req, res) => {
    return res.viewAsync('admin/schedule.hbs', {
        title: 'Schedule',
        heading: 'Schedule'
    })
})

fastify.get("/setup", async (req, res) => {
    return res.viewAsync("setup.hbs", { hello: "World" })
})

fastify.listen({ port: 3000}, (err, address) => {
    if (err) {
        fastify.log.error(err)
        process.exit(1)
    }
    recomputeAndBroadcast()
    console.log('[server] Fastify listening on port 3000')
})