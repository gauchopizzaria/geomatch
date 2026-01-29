import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "distanceValue", "distanceInput", "minAgeInput", "maxAgeInput", "ageDisplay"]

  connect() {
    this.updateDistanceVisual()
    this.updateAgeVisual()
  }

  open(event) {
    event.preventDefault()
    this.modalTarget.classList.remove("hidden")
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
  }

  updateDistanceVisual() {
    if (this.hasDistanceInputTarget) {
      this.distanceValueTarget.textContent = this.distanceInputTarget.value
    }
  }

  updateAgeVisual() {
    if (this.hasMinAgeInputTarget && this.hasMaxAgeInputTarget) {
      let min = parseInt(this.minAgeInputTarget.value)
      let max = parseInt(this.maxAgeInputTarget.value)

      // Lógica simples: Se min > max, empurra o max pra cima (ou vice versa)
      if (min > max) {
        // Opção A: Bloquear (Descomente abaixo se preferir)
        // this.minAgeInputTarget.value = max; min = max;
        
        // Opção B: Apenas visualmente aceitar por enquanto (o usuário se ajeita)
      }

      this.ageDisplayTarget.textContent = `${min} - ${max}`
    }
  }
  
  // Ação 'apply' não é necessária pois o botão é type="submit" e o form cuida do envio
}