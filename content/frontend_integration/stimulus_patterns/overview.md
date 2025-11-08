# Stimulus patterns & best practices

## What It Is

Stimulus is a JavaScript framework that connects existing HTML to controllers via data attributes. Instead of rendering views in JavaScript, you write small controllers that respond to events, update attributes, and manipulate the DOM. Stimulus hooks into the page lifecycle, calling `connect()` when a controller appears and `disconnect()` when it's removed.

## Why It Matters

Most Rails apps need some JavaScript: form validation, dropdowns, modals, live search. Traditional jQuery or vanilla JS leads to tangled code scattered across files. Stimulus organizes this into reusable controllers with clear lifecycle hooks, making it easy to attach behaviors to server-rendered HTML. This keeps JavaScript focused and testable while preserving Rails' server-side rendering strengths.

## When to Use

- Interactive widgets: autocomplete inputs, character counters, image previewers
- Inline validation: check username availability or password strength before submit
- Toggling visibility: show/hide filters, expand/collapse sections
- Fetching data: load dynamic content without Turbo Frames (e.g., search suggestions)
- Coordinating components: update multiple elements when one changes (e.g., quantity affects price)

## Three Common Pitfalls

1. **Forgetting to disconnect:** Event listeners or timers created in `connect()` must be removed in `disconnect()`, or you leak memory when Turbo replaces the page. Always clean up subscriptions, intervals, and external library instances.
2. **Overusing values for complex state:** Stimulus values sync to data attributes, triggering re-renders. For local-only state (like dropdown open/closed), use class properties instead of values to avoid unnecessary DOM writes.
3. **Tight coupling between controllers:** Accessing another controller's internal state via `this.element.querySelector` breaks encapsulation. Use outlets or custom events to communicate between controllers.

---

## Controller Lifecycle: connect and disconnect

Stimulus calls `connect()` when a controller mounts, and `disconnect()` when it unmounts:

```javascript
// app/javascript/controllers/timer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.intervalId = setInterval(() => {
      console.log("Tick")
    }, 1000)
  }

  disconnect() {
    clearInterval(this.intervalId)
  }
}

```

Use this pattern for setting up event listeners, third-party libraries, or timers. Always tear down in `disconnect()` to prevent memory leaks.

---

## Targets: Named DOM Elements

Define targets in your controller to reference elements by name:

```javascript
// app/javascript/controllers/dropdown_controller.js
export default class extends Controller {
  static targets = ["menu", "button"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
    this.buttonTarget.setAttribute("aria-expanded", !this.menuTarget.classList.contains("hidden"))
  }
}

```

In HTML:

```erb
<div data-controller="dropdown">
  <button data-dropdown-target="button" data-action="click->dropdown#toggle">Menu</button>
  <ul data-dropdown-target="menu" class="hidden">
    <li>Item 1</li>
  </ul>
</div>

```

Targets replace brittle `querySelector` calls with named references that fail loudly if missing.

---

## Values: Reactive Configuration

Values map data attributes to controller properties and trigger callbacks on change:

```javascript
// app/javascript/controllers/counter_controller.js
export default class extends Controller {
  static values = { count: Number }

  countValueChanged(value, previousValue) {
    this.element.textContent = value
  }

  increment() {
    this.countValue++
  }
}

```

HTML:

```erb
<div data-controller="counter" data-counter-count-value="0">
  0
</div>
<button data-action="click->counter#increment">+</button>

```

Values sync to the DOM, so updating `this.countValue` updates the `data-counter-count-value` attribute.

---

## Actions: Connecting Events to Methods

Actions bind events to controller methods:

```erb
<form data-controller="form-validator" data-action="submit->form-validator#validate">
  <input type="email" data-action="blur->form-validator#checkEmail">
</form>

```

Default event mappings: `click` for buttons, `submit` for forms, `input` for text fields. Override with `event->controller#method` syntax. Use `->` for bubbling or `@window->` for global events.

---

## Outlets: Connecting Controllers

Outlets reference other controllers on the page:

```javascript
// app/javascript/controllers/cart_controller.js
export default class extends Controller {
  static outlets = ["product"]

  addToCart() {
    this.productOutlets.forEach(product => {
      product.select()
    })
  }
}

```

HTML:

```erb
<div data-controller="cart" data-cart-product-outlet=".product">
  <div data-controller="product" class="product"></div>
  <button data-action="cart#addToCart">Add All</button>
</div>

```

Outlets avoid global variables and enable clean controller composition.

---

## Custom Events for Decoupling

Dispatch custom events to notify other controllers without direct references:

```javascript
// app/javascript/controllers/search_controller.js
export default class extends Controller {
  search() {
    const results = this.fetchResults()
    this.dispatch("resultsReady", { detail: { results } })
  }
}

```

Listen in another controller:

```javascript
// app/javascript/controllers/results_controller.js
export default class extends Controller {
  static targets = ["list"]

  handleResults(event) {
    this.listTarget.innerHTML = event.detail.results
  }
}

```

HTML:

```erb
<div data-controller="search" data-action="search:resultsReady@window->results#handleResults"></div>
<div data-controller="results" data-results-target="list"></div>

```

---

## Trade-offs Box

- **Advantage:** Minimal boilerplate for common UI patterns, integrates seamlessly with server-rendered HTML, and avoids build complexity.
- **Cost:** Not suited for managing deeply nested component trees or complex client-side routing; use React or Vue for those scenarios.
- **When to skip:** Apps with heavy client-side state management (e.g., multi-tab dashboards with shared state) benefit more from Redux or Zustand.

---

## Debugging Checklist

When things go wrong, check:

1. Verify `data-controller` attribute matches the registered controller name in `app/javascript/controllers`
2. Check Console for missing target errors: "Missing target element 'menu' for 'dropdown' controller"
3. Inspect `data-action` syntax: ensure format is `event->controller#method` with no typos
4. Confirm controller file exports `extends Controller` and is imported in `index.js`
5. Use Stimulus debug mode: add `window.Stimulus.debug = true` in `application.js` to log lifecycle events
6. Check that `connect()` runs by adding a `console.log` to verify the controller initializes

---

## One-Minute Recap

- Stimulus connects JavaScript controllers to HTML via data attributes, organizing UI behavior into reusable components
- Lifecycle hooks (`connect`, `disconnect`) manage setup and teardown to prevent memory leaks
- Targets name DOM elements, values sync configuration to attributes, actions bind events to methods
- Outlets reference other controllers for composition, while custom events enable decoupled communication
- Trade-off: simple for augmenting server-rendered HTML, but limited for complex client-side state or routing
