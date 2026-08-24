import { Controller } from "@hotwired/stimulus"

// Opening an article marks it read (D-feed-reader). Every reader worth
// using has done this since Google Reader: you clicked a headline, the item
// stopped being unread, and you never thought about it again. Without it,
// "unread" means "not explicitly dismissed", which is a different and much
// less useful thing — and it turns clearing a screen into two clicks per
// item.
//
// The click still does what it always did (open the source in a new tab);
// this rides alongside it and asks the server for the same Turbo Stream the
// Read button would have produced, so the row updates itself in place — or
// leaves the unread list, with its Undo — through exactly one code path.
export default class extends Controller {
  static values = { url: String }

  markRead(event) {
    // Only a plain left click means "I'm going to read this". A modifier or
    // a middle click is somebody stashing tabs, and it is not our business
    // to decide they've read them.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
      },
      credentials: "same-origin"
    })
      .then(response => (response.ok ? response.text() : null))
      .then(html => { if (html) window.Turbo.renderStreamMessage(html) })
      // A failed mark-read is not worth interrupting somebody's reading
      // for: the article still opened, and the row is still there to press.
      .catch(() => {})
  }
}
