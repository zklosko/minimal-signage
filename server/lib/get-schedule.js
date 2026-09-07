/**
 * Returns current and next item on the schedule.
 * 
 * TODO: replace this with real thing. Mock data for now.
 * @returns 
 */
export function getCurrentAndNextItem() {
    return {
        current: {
            kind: "empty",
            id: "empty",
            message: "Nothing scheduled yet"
        },
        next: undefined,
        msUntilNext: undefined
    }
}