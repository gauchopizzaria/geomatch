import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "map"]
  static values  = {
    minDuration: { type: Number, default: 600 },
    autoTimeout: { type: Number, default: 15000 }
  }

  connect() {
    this.startedAt = performance.now()
    this.element.addEventListener("map:loaded", this.hide)
    this.timeoutId = setTimeout(this.hide, this.autoTimeoutValue)
  }

  disconnect() {
    this.element.removeEventListener("map:loaded", this.hide)
    clearTimeout(this.timeoutId)
  }

  hide = () => {
    if (!this.hasOverlayTarget) return
    const elapsed   = performance.now() - this.startedAt
    const remaining = Math.max(0, this.minDurationValue - elapsed)

    setTimeout(() => {
      this.overlayTarget.classList.add("is-loaded")
      setTimeout(() => this.overlayTarget.remove(), 500)
    }, remaining)

    clearTimeout(this.timeoutId)
  }
}
