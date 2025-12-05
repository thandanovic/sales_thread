import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="slim-select"
export default class extends Controller {
  static values = {
    placeholder: { type: String, default: "Select..." },
    searchPlaceholder: { type: String, default: "Search..." },
    allowDeselect: { type: Boolean, default: true },
    closeOnSelect: { type: Boolean, default: true }
  }

  connect() {
    // Wait for SlimSelect to be available
    if (typeof SlimSelect === 'undefined') {
      console.warn('SlimSelect not loaded yet, waiting...')
      setTimeout(() => this.connect(), 100)
      return
    }

    this.slimSelect = new SlimSelect({
      select: this.element,
      settings: {
        placeholderText: this.placeholderValue,
        searchPlaceholder: this.searchPlaceholderValue,
        allowDeselect: this.allowDeselectValue,
        closeOnSelect: this.closeOnSelectValue,
        searchHighlight: true
      }
    })

    // Add dark mode class handling
    this.updateDarkMode()
    this.observer = new MutationObserver(() => this.updateDarkMode())
    this.observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })
  }

  disconnect() {
    if (this.slimSelect) {
      this.slimSelect.destroy()
    }
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  updateDarkMode() {
    const container = this.element.nextElementSibling
    if (container && container.classList.contains('ss-main')) {
      if (document.documentElement.classList.contains('dark')) {
        container.classList.add('ss-dark')
      } else {
        container.classList.remove('ss-dark')
      }
    }
  }
}
