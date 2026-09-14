import { defineRelations } from "drizzle-orm";
import { int, text, sqliteTable, primaryKey } from "drizzle-orm/sqlite-core";

export const content = sqliteTable("content", {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull(),
    src: text().notNull(),
    type: text({ enum: ["image", "video", "webpage"]}).notNull(),
    duration: int().notNull(),
})

export const playlist = sqliteTable("playlist", {
    id: int().primaryKey({ autoIncrement: true}),
    name: text().notNull()
})

export const screen = sqliteTable("screen", {
    id: int().primaryKey({ autoIncrement: true }),
    name: text().notNull(),
    playlistId: int().references(() => playlist.id)
})

export const settings = sqliteTable("settings", {
    id: text('id').primaryKey().default("default"),
    activePlaylistId: int().references(() => playlist.id),
    activeSince: int(),
})

export const contentToPlaylist = sqliteTable("content_to_playlist", 
    {
        contentId: int().notNull().references(() => content.id),
        playlistId: int().notNull().references(() => playlist.id),
        position: int().notNull().default(0)
    }, (t) => [primaryKey({ columns: [t.contentId, t.playlistId, t.position] } )]
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