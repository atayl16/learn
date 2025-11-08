# Hotwire: Frames & Streams

## What It Is

Turbo Frames and Turbo Streams are components of Hotwire that update page fragments without full reloads or custom JavaScript. Frames scope navigation to a specific DOM section, while Streams send targeted updates (append, prepend, replace, remove, update) from the server over HTTP or WebSocket.

## Why It Matters

Most web apps need partial page updates: adding comments, updating counters, refreshing lists. Traditional approaches require JavaScript-heavy SPAs or manual DOM manipulation. Turbo Frames and Streams deliver these updates through server-rendered HTML, reducing frontend complexity while maintaining snappy UX. This shifts logic back to Rails controllers where you already have authorization, database access, and view helpers.

## When to Use

- Inline editing: click an element, replace it with a form, submit, and swap back to updated content
- Lazy loading: defer rendering expensive content until a frame becomes visible
- Modal dialogs: load form content into a dialog without leaving the page
- Real-time notifications: broadcast new records to all connected clients via ActionCable
- Scoped navigation: paginate a table without reloading the page header and sidebar

## Three Common Pitfalls

1. **Mismatched frame IDs:** The response frame `id` must match the requesting frame's `id`, or Turbo ignores the update. Always verify `<turbo-frame id="...">` tags match on both request and response.
2. **Breaking out of frames unintentionally:** Links inside frames navigate only that frame unless marked `data-turbo-frame="_top"`. Forgetting this leaves the rest of the page stale or breaks navigation flow.
3. **Broadcasting to wrong stream name:** `turbo_stream_from` in views must match `broadcast_to` in models or jobs. A typo means updates never arrive. Check channel subscription in browser DevTools network tab.

---

## Turbo Frames: Scoped Navigation

Wrap a section of HTML in `<turbo-frame id="messages">`. Clicking links inside navigates only that frame:

```erb
<!-- app/views/messages/index.html.erb -->
<turbo-frame id="messages">
  <%= link_to "Next Page", messages_path(page: 2) %>
  <%= render @messages %>
</turbo-frame>
```

The response must also wrap content in `<turbo-frame id="messages">`. Turbo extracts that frame and swaps it in. The rest of the page stays untouched.

---

## Lazy Loading with Frames

Set `src` attribute to defer loading:

```erb
<turbo-frame id="expensive_stats" src="<%= stats_path %>">
  <p>Loading stats...</p>
</turbo-frame>
```

Turbo fires a GET request to `/stats` when the frame appears. The response replaces the loading message. Use this for dashboards or slow queries that shouldn't block initial page render.

---

## Turbo Streams: Targeted DOM Updates

Streams send multiple updates in one response. Common actions:

```ruby
# app/controllers/comments_controller.rb
def create
  @comment = @post.comments.create(comment_params)
  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.append("comments", partial: "comment", locals: { comment: @comment })
    end
  end
end
```

Available actions: `append`, `prepend`, `replace`, `remove`, `update`. Each targets a DOM ID and sends HTML to insert or replace.

---

## Broadcasting with ActionCable

Broadcast updates to all connected clients:

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  after_create_commit -> { broadcast_append_to "room_messages", target: "messages", partial: "messages/message" }
end
```

In the view, subscribe to the stream:

```erb
<%= turbo_stream_from "room_messages" %>
<div id="messages">
  <%= render @messages %>
</div>
```

When a new `Message` saves, all subscribers see it appended instantly. No polling, no custom WebSocket code.

---

## Form Submissions in Frames

Forms inside frames submit within the frame:

```erb
<turbo-frame id="edit_post_<%= post.id %>">
  <%= form_with model: post do |f| %>
    <%= f.text_field :title %>
    <%= f.submit %>
  <% end %>
</turbo-frame>
```

On success, return a frame with the updated content. On error, return the form with validation errors. The rest of the page remains stable.

---

## Trade-offs Box

- **Advantage:** Simplifies reactive UIs without JavaScript frameworks, reducing frontend maintenance and bundle size.
- **Cost:** Requires server round-trips for every update; not ideal for offline-first apps or heavy client-side interactions like drag-and-drop.
- **When to skip:** Complex state machines (multi-step wizards with local drafts) or apps needing offline support benefit more from React or Vue.

---

## Debugging Checklist

When things go wrong, check:

1. Inspect frame ID mismatches: open browser DevTools, find the requesting frame, and compare its `id` to the response frame's `id`
2. Verify `data-turbo="false"` isn't disabling Turbo on parent elements
3. Check the Network tab for the frame request and confirm the response contains a matching `<turbo-frame>` tag
4. For streams, confirm `turbo_stream_from` subscription in the view matches the broadcast channel name
5. Look for JavaScript errors in Console tab that might break Turbo initialization
6. Test with `data-turbo-frame="_top"` to confirm the issue is frame-scoping, not a routing or authorization problem

---

## One-Minute Recap

- Turbo Frames scope navigation to a DOM section, enabling lazy loading and inline editing without page reloads
- Turbo Streams send targeted updates (append, replace, remove) from server responses or ActionCable broadcasts
- Frame `id` must match between request and response or updates fail silently
- Broadcasting to connected clients requires matching `turbo_stream_from` and `broadcast_to` names
- Trade-off: server-driven simplicity vs. round-trip latency and limited offline capability
