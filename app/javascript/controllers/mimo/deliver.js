// Envio de mimos — usado por "Enviar um Mimo" (mimo_send_controller.js) e
// "Mimo do seu jeito" (mimo_custom_controller.js).
//
// POST /mimo/enviar (MimosController#deliver): com saldo suficiente o servidor paga com
// a carteira e responde { status: "sent" } (o aviso "Mimo enviado" vem no flash da
// próxima tela); sem saldo responde { status: "checkout", checkout_url } e a pessoa
// paga com Pix ou cartão no Mercado Pago.

export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || ""
}

export async function deliverMimo(url, payload) {
  let response
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify(payload)
    })
  } catch (_) {
    return { ok: false, error: "Sem conexão. Confira sua internet e tente de novo." }
  }

  const data = await response.json().catch(() => ({}))
  if (!response.ok) return { ok: false, error: data.error || "Não foi possível enviar o mimo. Tente de novo." }
  return { ok: true, data }
}

// Depois de enviar: volta para a tela de onde veio (conversa, perfil) ou abre o checkout
export function finishDelivery(data, doneUrl) {
  if (data.status === "checkout" && data.checkout_url) {
    window.location.href = data.checkout_url
    return
  }
  if (window.Turbo) window.Turbo.visit(doneUrl || "/", { action: "replace" })
  else window.location.replace(doneUrl || "/")
}

// "R$ 1.234,56"
export function formatMoney(cents) {
  const value = (Number(cents) || 0) / 100
  return `R$ ${value.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export function escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text == null ? "" : String(text)
  return div.innerHTML
}

// Máscara de celular BR: (00) 00000-0000
export function maskPhoneValue(value) {
  const digits = value.replace(/\D/g, "").slice(0, 11)
  if (digits.length > 10) return digits.replace(/(\d{2})(\d{5})(\d{0,4})/, "($1) $2-$3")
  if (digits.length > 6) return digits.replace(/(\d{2})(\d{4})(\d{0,4})/, "($1) $2-$3")
  if (digits.length > 2) return digits.replace(/(\d{2})(\d{0,5})/, "($1) $2")
  return digits.length ? `(${digits}` : ""
}
