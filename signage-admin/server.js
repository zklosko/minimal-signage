import express from 'express'
import { execFile } from 'child_process'
import expressBasicAuth from 'express-basic-auth'
import { readFile, writeFile } from 'fs'

const app = express()

const CONFIG_FILE = process.env.CONFIG_FILE || './config.json'
const COG_SERVICE = process.env.COG_SERVICE || 'cog-kiosk.service'
const PORT = process.env.PORT || 3000

app.use(expressBasicAuth({
    users: { admin: process.env.ADMIN_PASSWORD || 'changeme' },
    challenge: true
}))
app.use(express.json())
app.use(express.static('public'))

app.get('/config', async (req, res) => {
    try {
        const data = await readFile(CONFIG_FILE, 'utf-8')
        res.json(JSON.parse(data))
    } catch (e) {
        res.status(500).json({ ok: false, error: e.message })
    }
})

app.post('/config', async (req, res) => {
    const { url, refreshSeconds } = req.body

    try {
        new URL(url)
    } catch {
        return res.status(400).json({ ok: false, error: 'Invalid URL' })
    }

    try {
        await writeFile(CONFIG_FILE, JSON.stringify({ url, refreshSeconds }, null, 2))
    } catch (e) {
        return res.status(500).json({ ok: false, error: e.message })
    }

    execFile('sudo', ['/usr/bin/systemctl', 'restart', COG_SERVICE], (err) => {
        if (err) return res.status(500).json({ ok: false, error: err.message })
        res.json({ ok: true })
    })
})

app.listen(PORT, '0.0.0.0', () => console.log('Admin panel on :3000'))
