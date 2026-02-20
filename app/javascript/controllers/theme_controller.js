import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]
  static STORAGE_KEY = 'theme-preference'
  static DARK_MODE_CLASS = 'dark-mode'

  connect() {
    const currentTheme = this.getPreferredTheme()
    this.applyTheme(currentTheme)
  }

  getPreferredTheme() {
    const storedPreference = localStorage.getItem(this.constructor.STORAGE_KEY)
    if (storedPreference) return storedPreference
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  toggle() {
    const isDark = document.documentElement.classList.contains(this.constructor.DARK_MODE_CLASS)
    const newTheme = isDark ? "light" : "dark"
    this.applyTheme(newTheme)
    localStorage.setItem(this.constructor.STORAGE_KEY, newTheme)
  }

  applyTheme(theme) {
    const solIcon = this.data.get("solIcon")
    const luaIcon = this.data.get("luaIcon")

    if (theme === "dark") {
      document.documentElement.classList.add(this.constructor.DARK_MODE_CLASS)
      if (this.hasIconTarget) this.iconTarget.src = luaIcon
    } else {
      document.documentElement.classList.remove(this.constructor.DARK_MODE_CLASS)
      if (this.hasIconTarget) this.iconTarget.src = solIcon
    }
  }
}