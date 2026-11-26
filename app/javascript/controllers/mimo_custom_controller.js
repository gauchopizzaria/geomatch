import { Controller } from "@hotwired/stimulus"
import { deliverMimo, finishDelivery, formatMoney, maskPhoneValue } from "./mimo/deliver"

// "Mimo do seu jeito" (pages/mimo_custom.html.erb): o texto e o valor aparecem ao vivo na
// prévia "Como Fulano vai ver"; R$ 100 / 200 / 300 / 500 preenchem o valor; "Enviar
// mimo · R$ X" só libera com o nome escrito e o valor entre o mínimo e o máximo.
export default class extends Controller {
  static targets = [
    "phone", "label", "labelCount", "amount", "preset", "range", "note", "noteCount",
    "previewLabel", "previewPrice", "error", "send", "sendLabel", "payHint"
  ]

  static values = {
    deliverUrl: String, receiverId: String, balance: Number, doneUrl: String,
    min: Number, max: Number
  }

  connect() {
    this.cents = this.parseCents(this.amountTarget.value)
    this.sending = false
    this.refresh()
  }

  // ───────────── valor ─────────────
  // Digitação em centavos: "1" → 0,01 … "10000" → 100,00 (como nos apps de banco)
  typeAmount() {
    const digits = this.amountTarget.value.replace(/\D/g, "").replace(/^0+/, "").slice(0, 7)
    this.cents = Number(digits || 0)
    this.amountTarget.value = this.formatPlain(this.cents)
    this.refresh()
  }

  focusAmount() {
    const end = this.amountTarget.value.length
    requestAnimationFrame(() => this.amountTarget.setSelectionRange?.(end, end))
  }

  preset(event) {
    this.cents = Number(event.currentTarget.dataset.cents)
    this.amountTarget.value = this.formatPlain(this.cents)
    this.refresh()
  }

  // ───────────── prévia, contadores e botão ─────────────
  refresh() {
    const label = this.labelTarget.value.trim()
    this.labelCountTarget.textContent = `${this.labelTarget.value.length}/${this.labelTarget.maxLength}`
    this.noteCountTarget.textContent = `${this.noteTarget.value.length}/${this.noteTarget.maxLength}`

    this.previewLabelTarget.textContent = label || "Seu mimo"
    this.previewLabelTarget.classList.toggle("is-empty", !label)
    this.previewPriceTarget.textContent = formatMoney(this.cents)

    this.presetTargets.forEach((button) => button.classList.toggle("is-active", Number(button.dataset.cents) === this.cents))

    const inRange = this.cents >= this.minValue && this.cents <= this.maxValue
    this.rangeTarget.classList.toggle("is-invalid", this.cents > 0 && !inRange)

    this.sendLabelTarget.textContent = `Enviar mimo · ${formatMoney(this.cents)}`
    this.sendTarget.disabled = this.sending || !label || !inRange

    const viaCheckout = !this.receiverIdValue || this.balanceValue < this.cents
    this.payHintTarget.hidden = !viaCheckout
  }

  // ───────────── envio ─────────────
  async send() {
    if (this.sending || this.sendTarget.disabled) return

    const payload = {
      custom_label: this.labelTarget.value.trim(),
      amount_cents: this.cents,
      message: this.noteTarget.value.trim()
    }

    if (this.receiverIdValue) {
      payload.receiver_id = this.receiverIdValue
    } else {
      const phone = this.hasPhoneTarget ? this.phoneTarget.value.replace(/\D/g, "") : ""
      if (phone.length < 10) {
        this.showError("Informe o celular de quem vai receber, com DDD.")
        return
      }
      payload.phone = phone
    }

    this.setSending(true)
    const result = await deliverMimo(this.deliverUrlValue, payload)
    if (!result.ok) {
      this.setSending(false)
      this.showError(result.error)
      return
    }
    finishDelivery(result.data, this.doneUrlValue)
  }

  setSending(sending) {
    this.sending = sending
    this.sendTarget.classList.toggle("is-loading", sending)
    if (sending) this.errorTarget.hidden = true
    this.refresh()
  }

  showError(text) {
    this.errorTarget.textContent = text
    this.errorTarget.hidden = false
  }

  maskPhone(event) {
    event.target.value = maskPhoneValue(event.target.value)
  }

  // ───────────── auxiliares ─────────────
  parseCents(text) {
    return Number(String(text).replace(/\D/g, "") || 0)
  }

  // "100,00" (sem o R$, que fica fora do campo)
  formatPlain(cents) {
    return ((Number(cents) || 0) / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
