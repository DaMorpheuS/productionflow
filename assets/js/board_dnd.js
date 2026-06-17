// Native HTML5 drag-and-drop for the planning board. Delegated from the board
// root so it survives LiveView re-renders without re-binding per card.
//
// Cards carry data-route-step-id, data-machine-id (the machine the step belongs
// to) and, when already scheduled, data-scheduled-id. Drop zones carry
// data-machine-id (a machine id, or "backlog"). A card only drops on its own
// machine's column, or back onto the backlog. On drop we push the target zone
// and computed insertion index to the server, which is authoritative.
export const BoardDnD = {
  mounted() {
    this.dragged = null

    this.el.addEventListener("dragstart", (e) => {
      const card = e.target.closest("[data-draggable]")
      if (!card) return
      this.dragged = card
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", card.dataset.routeStepId || "")
      card.classList.add("opacity-40")
    })

    this.el.addEventListener("dragend", () => {
      if (this.dragged) this.dragged.classList.remove("opacity-40")
      this.dragged = null
    })

    this.el.addEventListener("dragover", (e) => {
      const zone = e.target.closest("[data-dropzone]")
      if (!zone || !this.dragged || !this.accepts(zone, this.dragged)) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      zone.classList.add("ring", "ring-primary/40")
    })

    this.el.addEventListener("dragleave", (e) => {
      const zone = e.target.closest("[data-dropzone]")
      if (zone && !zone.contains(e.relatedTarget)) {
        zone.classList.remove("ring", "ring-primary/40")
      }
    })

    this.el.addEventListener("drop", (e) => {
      const zone = e.target.closest("[data-dropzone]")
      if (!zone || !this.dragged || !this.accepts(zone, this.dragged)) return
      e.preventDefault()
      zone.classList.remove("ring", "ring-primary/40")

      this.pushEvent("drop", {
        scheduled_id: this.dragged.dataset.scheduledId || null,
        route_step_id: this.dragged.dataset.routeStepId || null,
        to_machine_id: zone.dataset.machineId,
        position: this.insertionIndex(zone, this.dragged, e.clientY),
      })
      this.dragged = null
    })
  },

  accepts(zone, card) {
    if (zone.dataset.machineId === "backlog") return !!card.dataset.scheduledId
    return zone.dataset.machineId === card.dataset.machineId
  },

  insertionIndex(zone, dragged, y) {
    const cards = [...zone.querySelectorAll("[data-draggable]")].filter((c) => c !== dragged)
    for (let i = 0; i < cards.length; i++) {
      const rect = cards[i].getBoundingClientRect()
      if (y < rect.top + rect.height / 2) return i
    }
    return cards.length
  },
}
