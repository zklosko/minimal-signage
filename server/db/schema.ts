import { defineRelations } from "drizzle-orm";
import { int, text, sqliteTable, primaryKey } from "drizzle-orm/sqlite-core";

export const content = sqliteTable("content", {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull(),
    url: text(),
    file: text(),
    duration: int().notNull()
})

export const playlist = sqliteTable("playlist", {
    id: int().primaryKey({ autoIncrement: true}),
    name: text().notNull()
})

export const contentToPlaylist = sqliteTable("content_to_playlist", 
    {
        contentId: int().notNull().references(() => content.id),
        playlistId: int().notNull().references(() => playlist.id),
        order: int().default(0)
    }, (t) => [primaryKey({ columns: [t.contentId, t.playlistId] } )]
)

export const relations = defineRelations({ content, playlist, contentToPlaylist },
    (r) => ({
        content: {
            playlist: r.many.playlist({
                from: r.content.id.through(r.contentToPlaylist.contentId),
                to: r.playlist.id.through(r.contentToPlaylist.playlistId)
            })
        },
        playlist: {
            participants: r.many.content()
        }
    })
)