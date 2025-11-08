# Exercise: Stimulus patterns & best practices

## Objective

Build a product search controller using targets, values, actions, and custom events to fetch and display results.

## Task

Create a Stimulus controller that:

1. **Search input with debouncing:** Add a text input with `data-action="input->search#handleInput"`. Use a Stimulus value to store the debounce delay (500ms). Clear the previous timeout on each input event and only fire the search after the delay.

2. **Loading state:** Add a target for a loading spinner. Show it when the search starts and hide it when results arrive. Use a boolean value `loading` to track state and trigger a value changed callback that toggles the spinner's visibility.

3. **Fetch results:** When the debounced search fires, fetch results from `/products/search?q=<query>` using `fetch()`. Dispatch a custom event `search:complete` with the results in the event detail.

4. **Display results:** Create a separate `results` controller that listens for `search:complete` events. Update a target element with the fetched HTML (assume the server returns a partial).

5. **Clear on disconnect:** Ensure the debounce timeout is cleared in `disconnect()` to prevent memory leaks when Turbo navigates away.

## Acceptance Criteria

- [ ] Typing in the search input waits 500ms after the last keystroke before firing the search request
- [ ] The loading spinner appears when the search starts and disappears when results load
- [ ] Search results populate in the results container without a page reload
- [ ] Multiple rapid keystrokes only trigger one search request after the debounce delay
- [ ] The `disconnect()` method clears the timeout, verifiable by adding a console.log
- [ ] Opening DevTools Console shows the custom `search:complete` event firing with result data

## Verification Steps

1. Run `rails server` and navigate to `/products`
2. Open DevTools Console and enable "Preserve log"
3. Type "laptop" in the search box and verify only one fetch request appears after 500ms
4. Confirm the loading spinner flashes briefly before results appear
5. Add `console.log` to `disconnect()` and navigate away; verify the log appears and no errors occur
6. Capture a screenshot of the Network tab showing the debounced `/products/search` request

## Stretch (Optional)

Add keyboard navigation: use arrow keys to highlight results and Enter to select. Store the selected index in a Stimulus value and update a CSS class on the highlighted item.

## Time Estimate

20 minutes
