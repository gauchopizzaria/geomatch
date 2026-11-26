import { Controller } from "@hotwired/stimulus"
import { deliverMimo, finishDelivery, escapeHtml, maskPhoneValue } from "./mimo/deliver"

// "Enviar um Mimo" (pages/mimo_catalog.html.erb)
//   - chips de categoria: tocar rola até a seção; rolar a tela acende o chip da seção
//   - tocar num mimo: marca o card, atualiza a barra de baixo e abre a folha
//     "escolha o tamanho" (Simples · Especial · Premium, com o Especial marcado)
//   - "Enviar rosa vermelha · R$ 4,90": paga com o saldo ou abre o checkout (deliver.js)
//   - (i): tela "Como funcionam os Mimos?"
const DEFAULT_TIER = "especial"

export default class extends Controller {
  static targets = [
    "phone", "chips", "chip", "section", "card",
    "bar", "barIcon", "barName",
    "sheet", "sheetIcon", "sheetName", "tiers", "message", "error", "send", "sendLabel", "payHint",
    "info"
  ]

  static values = { deliverUrl: String, receiverId: String, balance: Number, doneUrl: String }

  connect() {
    this.selected = this.cardTargets.find((card) => card.classList.contains("is-selected")) || null
    this.tier = DEFAULT_TIER
    this.sending = false

    this.onKeydown = (event) => {
      if (event.key !== "Escape") return
      if (!this.infoTarget.hidden) this.closeInfo()
      else if (!this.sheetTarget.hidden) this.closeSheet()
    }
    document.addEventListener("keydown", this.onKeydown)
    this.watchSections()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    this.sectionObserver?.disconnect()
    document.documentElement.classList.remove("ms-lock")
  }

  // ───────────── chips de categoria ─────────────
  jump(event) {
    const key = event.currentTarget.dataset.category
    const section = this.sectionTargets.find((el) => el.dataset.category === key)
    if (!section) return

    this.activateChip(key)
    this.jumping = true
    clearTimeout(this.jumpTimer)
    this.jumpTimer = setTimeout(() => { this.jumping = false }, 700)
    section.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  activateChip(key) {
    this.chipTargets.forEach((chip) => {
      const active = chip.dataset.category === key
      chip.classList.toggle("is-active", active)
      if (active) chip.setAttribute("aria-current", "true")
      else chip.removeAttribute("aria-current")
      // mantém o chip ativo visível na fileira (rola só a fileira, não a página)
      if (active && this.hasChipsTarget) {
        const row = this.chipsTarget
        const left = chip.offsetLeft - (row.clientWidth - chip.offsetWidth) / 2
        row.scrollTo({ left: Math.max(0, left), behavior: "smooth" })
      }
    })
  }

  // A seção que passa pelo meio de cima da tela acende o chip
  watchSections() {
    if (!("IntersectionObserver" in window) || !this.sectionTargets.length) return

    this.sectionObserver = new IntersectionObserver((entries) => {
      if (this.jumping) return
      const visible = entries.filter((entry) => entry.isIntersecting)
      if (!visible.length) return
      visible.sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
      this.activateChip(visible[0].target.dataset.category)
    }, { rootMargin: "-30% 0px -60% 0px" })

    this.sectionTargets.forEach((section) => this.sectionObserver.observe(section))
  }

  // ───────────── seleção e folha de tamanhos ─────────────
  choose(event) {
    this.select(event.currentTarget)
    this.openSheet()
  }

  select(card) {
    this.cardTargets.forEach((el) => el.classList.toggle("is-selected", el === card))
    this.selected = card
    this.barIconTarget.textContent = card.dataset.icon || "🎁"
    this.barNameTarget.textContent = card.dataset.name
    this.barTarget.hidden = false
  }

  openSheet() {
    if (!this.selected) return

    const card = this.selected
    this.tiersData = JSON.parse(card.dataset.tiers || "[]")
    this.tier = this.tiersData.some((t) => t.key === DEFAULT_TIER) ? DEFAULT_TIER : this.tiersData[0]?.key

    this.sheetIconTarget.textContent = card.dataset.icon || "🎁"
    this.sheetNameTarget.textContent = card.dataset.name
    this.tiersTarget.innerHTML = this.tiersData.map((tier) => `
      <button type="button" class="ms-tier" role="radio" data-tier="${escapeHtml(tier.key)}"
              data-action="mimo-send#pickTier">
        <span class="ms-tier-name">${escapeHtml(tier.name)}</span>
        <span class="ms-tier-label">${escapeHtml(tier.label)}</span>
        <strong class="ms-tier-price">${escapeHtml(tier.price)}</strong>
      </button>`).join("")

    this.hideError()
    this.refreshTier()
    this.sheetTarget.hidden = false
    document.documentElement.classList.add("ms-lock")
    requestAnimationFrame(() => this.sheetTarget.classList.add("is-open"))
    this.tiersTarget.querySelector('[aria-checked="true"]')?.focus({ preventScroll: true })
  }

  closeSheet() {
    if (this.sending) return
    this.sheetTarget.classList.remove("is-open")
    this.sheetTarget.hidden = true
    document.documentElement.classList.remove("ms-lock")
    this.selected?.focus({ preventScroll: true })
  }

  pickTier(event) {
    this.tier = event.currentTarget.dataset.tier
    this.refreshTier()
  }

  refreshTier() {
    const tier = this.currentTier()
    this.tiersTarget.querySelectorAll(".ms-tier").forEach((button) => {
      const active = button.dataset.tier === this.tier
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-checked", String(active))
    })
    if (!tier) return

    this.sendLabelTarget.textContent = `Enviar ${tier.label} · ${tier.price}`

    // Sem pessoa cadastrada (convite por celular) é sempre Pix/cartão; com pessoa, só
    // quando o saldo não cobre
    const viaCheckout = !this.receiverIdValue || this.balanceValue < tier.price_cents
    this.payHintTarget.hidden = !viaCheckout
    this.payHintTarget.textContent = this.receiverIdValue
      ? "Seu saldo não cobre este mimo: você paga com Pix ou cartão."
      : "O pagamento é por Pix ou cartão."
  }

  currentTier() {
    return (this.tiersData || []).find((tier) => tier.key === this.tier)
  }

  // ───────────── envio ─────────────
  async send() {
    if (this.sending || !this.selected) return
    const tier = this.currentTier()
    if (!tier) return

    const payload = {
      mimo_item_id: this.selected.dataset.itemId,
      tier: tier.key,
      message: this.messageTarget.value.trim()
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
    this.sendTarget.disabled = sending
    this.sendTarget.classList.toggle("is-loading", sending)
    if (sending) this.hideError()
  }

  showError(text) {
    this.errorTarget.textContent = text
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
  }

  maskPhone(event) {
    event.target.value = maskPhoneValue(event.target.value)
  }

  // ───────────── "Como funcionam os Mimos?" ─────────────
  openInfo() {
    this.infoTarget.hidden = false
    this.infoTarget.scrollTop = 0
    document.documentElement.classList.add("ms-lock")
    this.infoTarget.querySelector(".ms-back")?.focus({ preventScroll: true })
  }

  closeInfo() {
    this.infoTarget.hidden = true
    if (this.sheetTarget.hidden) document.documentElement.classList.remove("ms-lock")
    this.element.querySelector(".ms-info-btn")?.focus({ preventScroll: true })
  }
}
