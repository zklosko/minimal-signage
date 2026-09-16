import { defineConfig } from 'drizzle-kit';
import path from 'node:path'

export default defineConfig({
  out: './drizzle',
  schema: './db/schema.ts',
  dialect: 'sqlite',
  dbCredentials: {
    url: "file:" + path.resolve(process.cwd(), 'signage.db'),
  },
});
