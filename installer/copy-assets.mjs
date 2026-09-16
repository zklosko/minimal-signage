import { cp } from "node:fs/promises"

await cp("views", "dist/views", { recursive: true })
await cp("public", "dist/public", { recursive: true })