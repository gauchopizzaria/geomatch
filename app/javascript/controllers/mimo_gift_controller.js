import { Controller } from "@hotwired/stimulus"
import { launchConfetti } from "../confetti_animation.js"
import { csrfToken } from "./mimo/deliver"

// "Você ganhou um mimo" (pages/mimo_celebration.html.erb)
//   - "Agradecer a Fulano" sobe a folha: respostas rápidas (tocar põe a frase no começo
//     da mensagem, trocando a anterior) + "Sua mensagem" (até 200)
//   - "Enviar agradecimento": a mensagem vai para a conversa de vocês
//     (MimoThanksController); o botão vira "Agradecimento enviado" e o aviso
//     "Agradecimento enviado · Ver conversa" aparece no topo por alguns segundos
const TOAST_MS = 4500

export default class extends Controller {
  static targets = ["thankButton", "toast", "toastLink", "sheet", "quick", "message", "count", "error", "send"]
  static values = { thanksUrl: String, closeUrl: String }

  connect() {
    this.inserted = null // resposta rápida que está no começo da mensagem
    this.sending = false
    if (!this.thankButtonTarget.disabled) launchConfetti()

    this.onKeydown = (event) => { if (event.key === "Escape" && !this.sheetTarget.hidden) this.closeThanks() }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    clearTimeout(this.toastTimer)
    document.documentElement.classList.remove("ms-lock")
  }

  // X do topo: volta para onde estava; sem histórico, vai para a carteira
  close(event) {
    if (window.history.length > 1) {
      event.preventDefault()
      window.history.back()
    }
  }

  // ───────────── folha de agradecimento ─────────────
  openThanks() {
    if (this.thankButtonTarget.disabled) return
    this.sheetTarget.hidden = false
    document.documentElement.classList.add("ms-lock")
    requestAnimationFrame(() => this.sheetTarget.classList.add("is-open"))
    this.refresh()
  }

  closeThanks() {
    if (this.sending) return
    this.sheetTarget.classList.remove("is-open")
    this.sheetTarget.hidden = true
    document.documentElement.classList.remove("ms-lock")
    this.thankButtonTarget.focus({ preventScroll: true })
  }

  quick(event) {
    const text = event.currentTarget.dataset.text
    const field = this.messageTarget
    let value = field.value

    if (this.inserted && value.startsWith(this.inserted)) value = value.slice(this.inserted.length).replace(/^\s+/, "")
    value = value ? `${text} ${value}` : text

    field.value = value.slice(0, field.maxLength)
    this.inserted = text
    this.quickTargets.forEach((button) => {
      const active = button === event.currentTarget
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
    this.refresh()
    field.focus({ preventScroll: true })
    field.setSelectionRange(field.value.length, field.value.length)
  }

  typed() {
    // apagou a frase rápida: o chip deixa de estar marcado
    if (this.inserted && !this.messageTarget.value.startsWith(this.inserted)) {
      this.inserted = null
      this.quickTargets.forEach((button) => {
        button.classList.remove("is-active")
        button.setAttribute("aria-pressed", "false")
      })
    }
    this.refresh()
  }

  refresh() {
    const field = this.messageTarget
    this.countTarget.textContent = `${field.value.length}/${field.maxLength}`
    this.sendTarget.disabled = this.sending || field.value.trim().length === 0
  }

  // ───────────── envio ─────────────
  async send() {
    const message = this.messageTarget.value.trim()
    if (this.sending || !message) return

    this.sending = true
    this.errorTarget.hidden = true
    this.sendTarget.classList.add("is-loading")
    this.refresh()

    let ok = false
    let data = {}
    try {
      const response = await fetch(this.thanksUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ message })
      })
      data = await response.json().catch(() => ({}))
      ok = response.ok
    } catch (_) {
      data = { error: "Sem conexão. Confira sua internet e tente de novo." }
    }

    this.sending = false
    this.sendTarget.classList.remove("is-loading")

    if (!ok) {
      this.errorTarget.textContent = data.error || "Não foi possível enviar o agradecimento. Tente de novo."
      this.errorTarget.hidden = false
      this.refresh()
      return
    }

    this.closeThanks()
    this.markThanked()
    if (data.match_url) this.toastLinkTarget.href = data.match_url
    this.showToast()
  }

  markThanked() {
    const button = this.thankButtonTarget
    button.disabled = true
    button.classList.add("is-done")
    button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg> Agradecimento enviado'
  }

  showToast() {
    const toast = this.toastTarget
    toast.hidden = false
    requestAnimationFrame(() => toast.classList.add("is-visible"))
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => {
      toast.classList.remove("is-visible")
      setTimeout(() => { toast.hidden = true }, 300)
    }, TOAST_MS)
  }
}
