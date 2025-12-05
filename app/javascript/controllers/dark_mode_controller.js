import { Controller } from "@hotwired/stimulus"

// Handles dark mode toggle with localStorage persistence
export default class extends Controller {
  static targets = ["lightIcon", "darkIcon"]

  connect() {
    this.loadTheme()
    this.updateIcons()
  }

  toggle() {
    const html = document.documentElement
    const isDark = html.classList.contains("dark")

    if (isDark) {
      html.classList.remove("dark")
      this.saveTheme("light")
    } else {
      html.classList.add("dark")
      this.saveTheme("dark")
    }

    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("dark")

    if (this.hasLightIconTarget && this.hasDarkIconTarget) {
      if (isDark) {
        this.lightIconTarget.classList.add("hidden")
        this.darkIconTarget.classList.remove("hidden")
      } else {
        this.lightIconTarget.classList.remove("hidden")
        this.darkIconTarget.classList.add("hidden")
      }
    }
  }

  loadTheme() {
    const savedTheme = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches

    if (savedTheme === "dark" || (!savedTheme && prefersDark)) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }
  }

  saveTheme(theme) {
    localStorage.setItem("theme", theme)
    // Also set cookie for server-side rendering (optional)
    document.cookie = `dark_mode=${theme === "dark"}; path=/; max-age=31536000`
  }
}
