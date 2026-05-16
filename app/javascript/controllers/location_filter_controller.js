import { Controller } from "@hotwired/stimulus"

// Mapeamento nome completo → UF para a chamada à API do IBGE
const STATE_UF = {
  "Acre": "AC", "Alagoas": "AL", "Amapá": "AP", "Amazonas": "AM",
  "Bahia": "BA", "Ceará": "CE", "Distrito Federal": "DF",
  "Espírito Santo": "ES", "Goiás": "GO", "Maranhão": "MA",
  "Mato Grosso": "MT", "Mato Grosso do Sul": "MS", "Minas Gerais": "MG",
  "Pará": "PA", "Paraíba": "PB", "Paraná": "PR", "Pernambuco": "PE",
  "Piauí": "PI", "Rio de Janeiro": "RJ", "Rio Grande do Norte": "RN",
  "Rio Grande do Sul": "RS", "Rondônia": "RO", "Roraima": "RR",
  "Santa Catarina": "SC", "São Paulo": "SP", "Sergipe": "SE", "Tocantins": "TO"
}

export default class extends Controller {
  static targets = ["state", "city"]
  static values  = { currentCity: String }

  connect() {
    // Se a página carregar com um estado já selecionado (vindo do servidor),
    // recarrega as cidades do IBGE e re-seleciona a cidade filtrada.
    if (this.stateTarget.value) this.fetchCities()
  }

  async fetchCities() {
    const stateName = this.stateTarget.value
    const uf        = STATE_UF[stateName]

    this.cityTarget.innerHTML  = '<option value="">Carregando...</option>'
    this.cityTarget.disabled   = true

    if (!uf) {
      this.cityTarget.innerHTML = '<option value="">Cidade</option>'
      return
    }

    try {
      const res   = await fetch(`https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios`)
      const data  = await res.json()
      const names = data.map(c => c.nome).sort((a, b) => a.localeCompare(b, "pt-BR"))

      const opts = names.map(name => {
        const selected = name === this.currentCityValue ? ' selected' : ''
        return `<option value="${name}"${selected}>${name}</option>`
      }).join("")

      this.cityTarget.innerHTML = `<option value="">Cidade</option>${opts}`
      this.cityTarget.disabled  = false
    } catch (err) {
      console.warn("[LocationFilter] Erro ao consultar IBGE:", err)
      this.cityTarget.innerHTML = '<option value="">Erro ao carregar</option>'
      this.cityTarget.disabled  = true
    }
  }
}
