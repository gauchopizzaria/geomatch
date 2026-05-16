import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Toast carregado no DOM!")
    this._timer = setTimeout(() => this._dismiss(), 4000)
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  close() {
    clearTimeout(this._timer)
    this._dismiss()
  }

  _dismiss() {
    this.element.classList.add("toast--hiding")
    this.element.addEventListener("animationend", () => this.element.remove(), { once: true })
  }
}
