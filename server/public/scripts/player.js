const stage = document.getElementById("stage")
let preloaded = null

function build(item) {
    switch (item.kind) {
        case "image":
            const img = document.createElement("img")
            img.src = item.url
            return img
        case "video":
            const video = document.createElement("video")
            video.src = item.url
            video.autoplay = true
            video.muted = true
            return video
        case "text":
            const div = document.createElement("div")
            div.className = "text-slide"
            div.textContent = item.textContent
            if (item.style) Object.assign(div.style, item.style)
            return div
        case "webpage":
            const webpage = document.createElement("iframe")
            webpage.src = item.url
            return webpage
    }

    const div = document.createElement("div")
    div.className = "idle"
    return div
}

function mount(item, el) {
    if (el) {
        el.style.display = ""
        stage.replaceChildren(el)
        return
    }
    stage.replaceChildren(build(item))
}

function preload(item) {
    if (item.kind === "text" || item.kind === "empty") {
        preloaded = { item, el: build(item)}
        return
    }
    const el = build(item)
    el.style.display = "none"
    document.body.appendChild(el)
    preloaded = { item, el }
}

const source = new EventSource("/player/events")

source.addEventListener("item", (evt) => {
    const data = JSON.parse(evt.data)

    if (preloaded && preloaded.item.id === data.current.id) {
        preloaded.el.remove()
        mount(data.current, preloaded.el)
    } else {
        mount(data.current)
    }
    preloaded = null

    if (data.next) preload(data.next)
})