import { Controller } from "@hotwired/stimulus"

// Handles dropdown menus (user menu, notifications, etc.)
export default class extends Controller {
  static targets = ["menu", "button"]
  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    // Close dropdown when clicking outside
    this.clickOutsideHandler = this.clickOutside.bind(this)
    document.addEventListener("click", this.clickOutsideHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
  }

  toggle(event) {
    event.stopPropagation()
    this.openValue = !this.openValue
    this.updateDisplay()
  }

  close() {
    this.openValue = false
    this.updateDisplay()
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  updateDisplay() {
    if (this.hasMenuTarget) {
      if (this.openValue) {
        this.menuTarget.classList.remove("hidden")
      } else {
        this.menuTarget.classList.add("hidden")
      }
    }
  }
}
