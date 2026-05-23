import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "slide", "indicator", "like", "nope", "profileModal", "btnLike", "btnReject"]

  static values = {
    currentSlide: { type: Number, default: 0 },
    slideCount:   { type: Number, default: 0 }
  }

  // ============================================================
  // LIFECYCLE
  // ============================================================
  connect() {
    this.slideCountValue = this.slideTargets.length
    this.isDragging  = false
    this.pointerId   = null
    this.startX      = 0
    this.startY      = 0
    this.currentX    = 0
    this.currentY    = 0

    // Bindings salvos para remoção limpa no disconnect
    this._onDown   = this.handleStart.bind(this)
    this._onMove   = this.handleMove.bind(this)
    this._onUp     = this.handleEnd.bind(this)

    if (this.hasCardTarget) {
      this.cardTarget.style.cursor = 'grab'
      this.cardTarget.style.touchAction = 'none'
      this.cardTarget.addEventListener('pointerdown',  this._onDown)
      this.cardTarget.addEventListener('dragstart',    e => e.preventDefault())
    }

    // Move/Up no window para capturar quando o ponteiro sai do card
    window.addEventListener('pointermove',  this._onMove)
    window.addEventListener('pointerup',    this._onUp)
    window.addEventListener('pointercancel',this._onUp)

    this.updateGallery()
  }

  disconnect() {
    if (this.hasCardTarget) {
      this.cardTarget.removeEventListener('pointerdown', this._onDown)
    }
    window.removeEventListener('pointermove',   this._onMove)
    window.removeEventListener('pointerup',     this._onUp)
    window.removeEventListener('pointercancel', this._onUp)
  }

  // ============================================================
  // MODAL DE PERFIL COMPLETO
  // ============================================================
  openProfile(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (this.hasProfileModalTarget) {
      this.profileModalTarget.classList.add("open")
      document.body.style.overflow = "hidden"
    }
  }

  closeProfile(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (this.hasProfileModalTarget) {
      this.profileModalTarget.classList.remove("open")
      document.body.style.overflow = ""
    }
  }

  // ============================================================
  // POINTER EVENTS — DRAG
  // ============================================================
  handleStart(event) {
    // Ignora se o perfil estiver aberto
    if (this.hasProfileModalTarget && this.profileModalTarget.classList.contains("open")) return
    // Ignora cliques em botões e na área de info clicável
    if (event.target.closest('button') || event.target.closest('.clickable-info')) return
    // Ignora toques adicionais enquanto já está arrastando
    if (this.isDragging) return

    this.isDragging = true
    this.pointerId  = event.pointerId

    this.startX   = event.clientX
    this.startY   = event.clientY
    this.currentX = event.clientX
    this.currentY = event.clientY

    if (this.hasCardTarget) {
      this.cardTarget.style.transition = 'none'
      this.cardTarget.style.cursor     = 'grabbing'
    }
  }

  handleMove(event) {
    if (!this.isDragging || event.pointerId !== this.pointerId) return

    const deltaX = event.clientX - this.startX
    const deltaY = event.clientY - this.startY

    // Bloqueia scroll vertical nativo durante arrasto horizontal
    if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 5) {
      event.preventDefault()
    }

    this.currentX = event.clientX
    this.currentY = event.clientY

    this._updateVisuals(deltaX, deltaY)
  }

  handleEnd(event) {
    if (!this.isDragging || event.pointerId !== this.pointerId) return

    this.isDragging = false
    this.pointerId  = null

    if (this.hasCardTarget) this.cardTarget.style.cursor = 'grab'

    const deltaX    = this.currentX - this.startX
    const THRESHOLD = 120

    if (Math.abs(deltaX) > THRESHOLD) {
      this._throwCard(deltaX > 0 ? 'like' : 'reject')
    } else {
      this._resetCard()
    }
  }

  // ============================================================
  // VISUAIS — ARRASTO
  // ============================================================
  _updateVisuals(deltaX, deltaY) {
    if (!this.hasCardTarget) return

    const rotation = deltaX / 18
    const lift     = deltaY * 0.25
    this.cardTarget.style.transform = `translateX(${deltaX}px) translateY(${lift}px) rotate(${rotation}deg)`

    // Opacidade proporcional à distância — máximo 1 a partir de 100px
    const progress = Math.min(1, Math.abs(deltaX) / 100)

    if (deltaX > 0) {
      if (this.hasLikeTarget) this.likeTarget.style.opacity = progress
      if (this.hasNopeTarget) this.nopeTarget.style.opacity = 0
      if (this.hasBtnLikeTarget)   this.btnLikeTarget.classList.toggle('btn-highlight', progress > 0.3)
      if (this.hasBtnRejectTarget) this.btnRejectTarget.classList.remove('btn-highlight')
    } else if (deltaX < 0) {
      if (this.hasNopeTarget) this.nopeTarget.style.opacity = progress
      if (this.hasLikeTarget) this.likeTarget.style.opacity = 0
      if (this.hasBtnRejectTarget) this.btnRejectTarget.classList.toggle('btn-highlight', progress > 0.3)
      if (this.hasBtnLikeTarget)   this.btnLikeTarget.classList.remove('btn-highlight')
    } else {
      if (this.hasLikeTarget) this.likeTarget.style.opacity = 0
      if (this.hasNopeTarget) this.nopeTarget.style.opacity = 0
      if (this.hasBtnLikeTarget)   this.btnLikeTarget.classList.remove('btn-highlight')
      if (this.hasBtnRejectTarget) this.btnRejectTarget.classList.remove('btn-highlight')
    }
  }

  _resetCard() {
    if (!this.hasCardTarget) return
    this.cardTarget.style.transition = 'transform 0.4s cubic-bezier(0.2, 0.8, 0.2, 1)'
    this.cardTarget.style.transform  = 'translateX(0) translateY(0) rotate(0deg)'
    if (this.hasLikeTarget)      this.likeTarget.style.opacity = 0
    if (this.hasNopeTarget)      this.nopeTarget.style.opacity = 0
    if (this.hasBtnLikeTarget)   this.btnLikeTarget.classList.remove('btn-highlight')
    if (this.hasBtnRejectTarget) this.btnRejectTarget.classList.remove('btn-highlight')
  }

  // ============================================================
  // AÇÃO — VOAR PARA FORA + SUBMETER
  // ============================================================
  _throwCard(type) {
    if (!this.hasCardTarget) return

    const isLike = type === 'like'
    const endX   = isLike ? window.innerWidth * 1.6 : -window.innerWidth * 1.6

    // Overlay no máximo durante o voo
    if (isLike  && this.hasLikeTarget) this.likeTarget.style.opacity = 1
    if (!isLike && this.hasNopeTarget) this.nopeTarget.style.opacity = 1

    this.cardTarget.style.transition = 'transform 0.45s ease-in, opacity 0.4s ease-in'
    this.cardTarget.style.transform  = `translateX(${endX}px) rotate(${isLike ? 35 : -35}deg)`
    this.cardTarget.style.opacity    = '0'

    const btn = document.querySelector(isLike ? '.btn-like' : '.btn-reject')
    if (btn) {
      setTimeout(() => btn.click(), 250)
    } else {
      setTimeout(() => location.reload(), 600)
    }
  }

  // ============================================================
  // GALERIA DE FOTOS
  // ============================================================
  nextSlide(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (this.slideCountValue <= 1) return
    this.currentSlideValue = (this.currentSlideValue + 1) % this.slideCountValue
  }

  prevSlide(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    if (this.slideCountValue <= 1) return
    this.currentSlideValue = (this.currentSlideValue - 1 + this.slideCountValue) % this.slideCountValue
  }

  currentSlideValueChanged() { this.updateGallery() }

  updateGallery() {
    this.slideTargets.forEach((s, i)   => s.classList.toggle('active', i === this.currentSlideValue))
    this.indicatorTargets.forEach((d, i) => d.classList.toggle('active', i === this.currentSlideValue))
  }
}
