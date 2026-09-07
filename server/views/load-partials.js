import Handlebars from "handlebars";
import { readdir, readFile } from "node:fs/promises"
import path from "node:path"

export async function loadPartials(directory) {
    const files = await readdir(directory)

    for (const file of files) {
        if (!file.endsWith(".hbs")) {
            continue
        }

        const name = path.basename(file, ".hbs")
        const content = await readFile(
            path.join(directory, file), "utf8"
        )

        Handlebars.registerPartial(name, content)
    }
}