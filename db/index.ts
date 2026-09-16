import { createClient } from '@libsql/client'
import path from 'node:path'
import { drizzle } from 'drizzle-orm/libsql'

const client = createClient({ url: "file:" + path.resolve(process.cwd(), 'signage.db') })
export const db = drizzle({ client })