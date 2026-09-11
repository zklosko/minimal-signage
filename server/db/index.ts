import { createClient } from '@libsql/client'
import 'dotenv/config'
import { drizzle } from 'drizzle-orm/libsql'

const dbFile = process.env.DB_FILE_NAME
if (!dbFile) throw new Error (`DB_FILE_NAME is not set in .env!`)

    const client = createClient({ url: dbFile })
export const db = drizzle({ client })