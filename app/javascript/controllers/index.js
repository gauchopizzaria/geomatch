// Importa o Stimulus Application
import { Application } from "@hotwired/stimulus"
import ConfettiController from "./confetti_controller.js"
application.register("confetti", ConfettiController)

// Cria a instância da aplicação Stimulus
const application = Application.start()

// Importa automaticamente todos os controllers do diretório atual
const controllers = import.meta.globEager("./**/*_controller.js")

for (const path in controllers) {
  const controller = controllers[path].default
  if (controller && controller.identifier) {
    application.register(controller.identifier, controller)
  }
}

export { application }
