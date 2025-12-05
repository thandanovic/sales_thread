import { Controller } from "@hotwired/stimulus"

// Handles sidebar collapse/expand and mobile menu toggle
export default class extends Controller {
  static targets = ["sidebar", "overlay", "collapseIcon", "expandIcon", "mainContent"]
  static values = {
    collapsed: { type: Boolean, default: false }
  }

  connect() {
    this.loadState()
    this.updateDisplay()
  }

  toggle() {
    if (this.isMobile()) {
      this.toggleMobile()
    } else {
      this.toggleCollapse()
    }
  }

  toggleCollapse() {
    this.collapsedValue = !this.collapsedValue
    this.saveState()
    this.updateDisplay()
  }

  toggleMobile() {
    const sidebar = this.sidebarTarget
    const overlay = this.hasOverlayTarget ? this.overlayTarget : null

    if (sidebar.classList.contains("-translate-x-full")) {
      sidebar.classList.remove("-translate-x-full")
      if (overlay) overlay.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    } else {
      sidebar.classList.add("-translate-x-full")
      if (overlay) overlay.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
    }
  }

  closeMobile() {
    const sidebar = this.sidebarTarget
    const overlay = this.hasOverlayTarget ? this.overlayTarget : null

    sidebar.classList.add("-translate-x-full")
    if (overlay) overlay.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  updateDisplay() {
    const sidebar = this.sidebarTarget
    const mainContent = this.hasMainContentTarget ? this.mainContentTarget : document.querySelector('.page-transition')

    if (this.collapsedValue) {
      // Collapsed state
      sidebar.classList.add("lg:w-20")
      sidebar.classList.remove("lg:w-72")
      sidebar.classList.add("sidebar-collapsed")
      sidebar.classList.remove("sidebar-expanded")

      // Update main content margin
      if (mainContent) {
        mainContent.classList.remove("lg:ml-72")
        mainContent.classList.add("lg:ml-20")
      }

      // Update icons
      if (this.hasCollapseIconTarget) this.collapseIconTarget.classList.add("hidden")
      if (this.hasExpandIconTarget) this.expandIconTarget.classList.remove("hidden")
    } else {
      // Expanded state
      sidebar.classList.remove("lg:w-20")
      sidebar.classList.add("lg:w-72")
      sidebar.classList.remove("sidebar-collapsed")
      sidebar.classList.add("sidebar-expanded")

      // Update main content margin
      if (mainContent) {
        mainContent.classList.add("lg:ml-72")
        mainContent.classList.remove("lg:ml-20")
      }

      // Update icons
      if (this.hasCollapseIconTarget) this.collapseIconTarget.classList.remove("hidden")
      if (this.hasExpandIconTarget) this.expandIconTarget.classList.add("hidden")
    }

    // Dispatch event for other components to react
    this.dispatch("toggled", { detail: { collapsed: this.collapsedValue } })
  }

  isMobile() {
    return window.innerWidth < 1024
  }

  saveState() {
    localStorage.setItem("sidebarCollapsed", this.collapsedValue)
  }

  loadState() {
    const saved = localStorage.getItem("sidebarCollapsed")
    if (saved !== null) {
      this.collapsedValue = saved === "true"
    }
  }
}
