import { eq } from "drizzle-orm"
import { db } from "../db/index.js"
import { content, contentToPlaylist, settings } from "../db/schema.js"

async function getActivePlaylist(): Promise<number> {
    const settingsQuery = await db
        .select()
        .from(settings)
        .where(eq(settings.id, "default"))
        .get()

    console.log("[db] active playlist:", settingsQuery) // TESTING
    return settingsQuery?.activePlaylistId ?? 0
}
async function getSchedule(activePlaylistId: number) { 
    const items = await db
        .select({
            id: content.id,
            type: content.type,
            src: content.src,
            duration: content.duration,
            position: contentToPlaylist.position,
        })
        .from(contentToPlaylist)
        .innerJoin(
            content,
            eq(contentToPlaylist.contentId, content.id)
        )
        .where(eq(contentToPlaylist.playlistId, activePlaylistId))
        .orderBy(contentToPlaylist.position)

    return items
}

function generateNotScheduledMessage() {
    return {
        type: "empty",
        id: "empty",
        src: "",
        message: "Nothing scheduled yet"
    }
}


/**
 * Returns current and next item on the schedule.
 * @returns 
 */
export async function getScheduleUpdate() {
    const activePlaylistId = await getActivePlaylist()
    if (!activePlaylistId) {
        const notScheduledMsg = generateNotScheduledMessage()
        return {
            current: notScheduledMsg,
            next: notScheduledMsg,
            msUntilNext: undefined,
        }
    }

    const schedule = await getSchedule(activePlaylistId)
    if (schedule.length === 0) {
        const notScheduledMsg = generateNotScheduledMessage()
        return {
            current: notScheduledMsg,
            next: notScheduledMsg,
            msUntilNext: undefined,
        }
    }

    console.log("[schedule]", schedule) // TESTING

    const totalDuration = schedule.reduce(
        (total, item) => total + item.duration, 0
    )
    const elapsed = (Date.now() / 1000 ) % totalDuration
    let position = 0

    for (let i = 0; i < schedule.length; i++) {
        const item = schedule[i]
        const end = position + item.duration

        if (elapsed < end) {
            const next = schedule[(i+1) % schedule.length]
            const secondsUntilNext = end - elapsed

            return {
                current: item,
                next,
                msUntilNext: secondsUntilNext * 1000
            }
        }

        position = end
    }

    return {
        current: schedule[0],
        next: schedule[1] ?? schedule[0],
        msUntilNext: schedule[0].duration * 1000,
    }
}