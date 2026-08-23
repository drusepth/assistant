import { Controller } from "@hotwired/stimulus"

// The task-completion party (D-task-celebration). The server decides *whether*
// and *how big* (Tasks::Celebration) and leaves the verdict in the flash; this
// draws it: a confetti cannon, a banner that pops, and — for the big tiers —
// fireworks and a shake.
//
// It fires from `tokenValueChanged` rather than `connect` on purpose. The app
// morphs on redirect-to-self (see the layout's turbo-refresh-method), so after
// the first celebration this element is already in the DOM and connect() never
// runs again; a fresh token on the next completion does trip the value
// callback, and every finished task gets its confetti.
//
// Everything is drawn on one canvas the controller owns and throws away, so
// nothing here survives the animation.
const TIERS = {
  task: { confetti: 90, fireworks: 0, shake: false, emoji: [] },
  streak: { confetti: 150, fireworks: 1, shake: false, emoji: ["🔥"] },
  goal: { confetti: 220, fireworks: 2, shake: true, emoji: ["🎉", "⭐"] },
  board: { confetti: 320, fireworks: 5, shake: true, emoji: ["🎉", "🎊", "🏆", "✨"] }
}

// Warm ramp + sage, so the confetti is the app's own palette rather than
// party-store primaries.
const COLORS = ["#d67f48", "#f6a06b", "#ffc6a5", "#8fa073", "#ccdbb2", "#f2ebe0", "#c67139"]

const GRAVITY = 0.24
const DRAG = 0.992

export default class extends Controller {
  static values = { tier: String, headline: String, note: String, token: String }

  initialize() {
    this.timers = []
    this.particles = []
    this.pendingBursts = 0
  }

  disconnect() {
    this.stop()
  }

  // Stimulus calls this once on connect (with the initial token) and again
  // whenever a morph swaps a new one in — one call per celebration, either way.
  tokenValueChanged(token) {
    if (!token) return

    this.stop()
    this.element.replaceChildren()

    const tier = TIERS[this.tierValue] || TIERS.task
    this.banner(tier)

    // A user who asked the OS for less motion gets the banner and nothing
    // that flies: same news, no fireworks.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.startCanvas()
    this.cannons(tier)
    if (tier.shake) this.shake()

    this.pendingBursts = tier.fireworks
    for (let i = 0; i < tier.fireworks; i++) {
      this.timers.push(setTimeout(() => this.firework(), 350 + i * 320))
    }
    this.frame = requestAnimationFrame(this.tick)
  }

  // ---- the banner -----------------------------------------------------

  // Not on the canvas: it's the one part of the celebration that is also
  // information ("which task, and why the fuss"), so it stays real text a
  // screen reader can announce.
  banner(tier) {
    const banner = document.createElement("div")
    banner.className = tier.shake ? "celebrate-banner celebrate-banner-big" : "celebrate-banner"

    const headline = document.createElement("p")
    // `display` is the brand-voice atom (docs/DESIGN.md): composed here, not
    // baked into .celebrate-headline, because it can't be @apply-ed.
    headline.className = "display celebrate-headline"
    headline.textContent = this.headlineValue || "Done!"
    banner.append(headline)

    if (this.noteValue) {
      const note = document.createElement("p")
      note.className = "celebrate-note"
      note.textContent = this.noteValue
      banner.append(note)
    }

    // The rig lives in the layout for the life of the page, so the banner
    // clears itself when its own animation ends rather than waiting for a
    // navigation — and survives the teardown that stops the confetti.
    banner.addEventListener("animationend", () => banner.remove())
    this.element.append(banner)
  }

  shake() {
    document.body.classList.add("celebrate-shake")
    this.timers.push(setTimeout(() => document.body.classList.remove("celebrate-shake"), 600))
  }

  // ---- the confetti ---------------------------------------------------

  startCanvas() {
    this.canvas = document.createElement("canvas")
    this.canvas.style.width = "100%"
    this.canvas.style.height = "100%"
    this.element.append(this.canvas)

    // Capped at 2: a 3x phone screen triples the fill cost for pixels nobody
    // can see on confetti this size.
    this.ratio = Math.min(window.devicePixelRatio || 1, 2)
    this.width = this.element.clientWidth
    this.height = this.element.clientHeight
    this.canvas.width = this.width * this.ratio
    this.canvas.height = this.height * this.ratio
    this.ctx = this.canvas.getContext("2d")
    this.ctx.scale(this.ratio, this.ratio)
  }

  // Two bottom-corner cannons firing inwards, plus a pop out of the middle —
  // the shape everyone reads instantly as "something good happened".
  cannons(tier) {
    const perCannon = Math.round(tier.confetti * 0.4)
    this.burst(perCannon, { x: 0, y: this.height, angle: -Math.PI / 3, spread: 0.85, power: 28, tier })
    this.burst(perCannon, { x: this.width, y: this.height, angle: (-Math.PI * 2) / 3, spread: 0.85, power: 28, tier })
    this.burst(tier.confetti - perCannon * 2, {
      x: this.width / 2, y: this.height * 0.45, angle: -Math.PI / 2, spread: Math.PI, power: 13, tier
    })
  }

  firework() {
    this.pendingBursts -= 1
    if (!this.ctx) return

    this.burst(60, {
      x: this.width * (0.2 + Math.random() * 0.6),
      y: this.height * (0.15 + Math.random() * 0.35),
      angle: -Math.PI / 2, spread: Math.PI * 2, power: 12,
      tier: TIERS[this.tierValue] || TIERS.task
    })
  }

  burst(count, { x, y, angle, spread, power, tier }) {
    for (let i = 0; i < count; i++) {
      const direction = angle + (Math.random() - 0.5) * spread
      const speed = power * (0.45 + Math.random() * 0.75)
      // A tenth of the pieces are emoji on the tiers that have them: enough
      // to register, not so many it turns into a sticker sheet.
      const emoji = tier.emoji.length && Math.random() < 0.1
        ? tier.emoji[Math.floor(Math.random() * tier.emoji.length)]
        : null

      this.particles.push({
        x, y,
        vx: Math.cos(direction) * speed,
        vy: Math.sin(direction) * speed,
        w: 6 + Math.random() * 8,
        h: 4 + Math.random() * 8,
        rotation: Math.random() * Math.PI * 2,
        spin: (Math.random() - 0.5) * 0.3,
        color: COLORS[Math.floor(Math.random() * COLORS.length)],
        emoji,
        round: !emoji && Math.random() < 0.3,
        life: 0,
        span: 90 + Math.random() * 70
      })
    }
  }

  tick = () => {
    const { ctx } = this
    if (!ctx) return

    ctx.clearRect(0, 0, this.width, this.height)

    for (const p of this.particles) {
      p.life += 1
      p.vy += GRAVITY
      p.vx *= DRAG
      p.vy *= DRAG
      p.x += p.vx
      p.y += p.vy
      p.rotation += p.spin

      ctx.save()
      ctx.globalAlpha = this.fade(p)
      ctx.translate(p.x, p.y)
      ctx.rotate(p.rotation)
      if (p.emoji) {
        ctx.font = `${p.w * 2.4}px serif`
        ctx.textAlign = "center"
        ctx.fillText(p.emoji, 0, 0)
      } else if (p.round) {
        ctx.fillStyle = p.color
        ctx.beginPath()
        ctx.arc(0, 0, p.w / 2, 0, Math.PI * 2)
        ctx.fill()
      } else {
        ctx.fillStyle = p.color
        // Squashing the height as it spins is what sells the tumble.
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h * Math.abs(Math.cos(p.rotation)))
      }
      ctx.restore()
    }

    this.particles = this.particles.filter((p) => p.life < p.span && p.y < this.height + 40)

    if (this.particles.length || this.pendingBursts > 0) {
      this.frame = requestAnimationFrame(this.tick)
    } else {
      this.stop()
    }
  }

  // Full opacity for the first 60% of a piece's life, then out.
  fade(p) {
    const dying = Math.max(0, p.life - p.span * 0.6)
    return Math.max(0, 1 - dying / (p.span * 0.4))
  }

  stop() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    this.timers.forEach(clearTimeout)
    this.timers = []
    this.pendingBursts = 0
    this.particles = []
    document.body.classList.remove("celebrate-shake")
    this.canvas?.remove()
    this.canvas = null
    this.ctx = null
  }
}
