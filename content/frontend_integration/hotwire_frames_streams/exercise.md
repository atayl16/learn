# Exercise: Hotwire: Frames & Streams

## Objective

Build a real-time comment feed using Turbo Frames for inline editing and Turbo Streams for live broadcasts.

## Task

You have a Rails app with `Post` and `Comment` models. Implement:

1. **Comments list with lazy loading:** Wrap the comments section in a Turbo Frame with `src` that loads from `post_comments_path(post)`. Show "Loading comments..." placeholder.

2. **Inline editing:** Add an "Edit" link next to each comment that replaces the comment text with a Turbo Frame containing a form. On submit, update the comment and swap the frame back to the rendered comment.

3. **Live comment creation:** When a new comment is created, broadcast it to all users viewing the post using `broadcast_append_to`. Subscribe using `turbo_stream_from` in the post view.

4. **Form submission in frame:** Create a new comment form at the bottom of the comments list inside a Turbo Frame. On successful submission, append the new comment via Turbo Stream and clear the form.

## Acceptance Criteria

- [ ] Comments section lazy-loads when the page renders, showing placeholder text until the GET request completes
- [ ] Clicking "Edit" on a comment swaps only that comment's content to an editable form without reloading the page
- [ ] Submitting the edit form updates the comment and returns the updated HTML in the same frame
- [ ] Creating a new comment broadcasts to all connected clients, appending it to the `#comments` container
- [ ] The new comment form clears after successful submission while staying in the same frame
- [ ] Opening the post in two browser tabs shows new comments appearing in both tabs simultaneously

## Verification Steps

1. Run `rails server` and open `http://localhost:3000/posts/1` in two browser tabs
2. In the browser DevTools Network tab, confirm the lazy-loaded comments frame triggers a GET to `/posts/1/comments`
3. Submit a new comment in tab 1 and verify it appears in tab 2 without refreshing
4. Click "Edit" on a comment, confirm only that comment changes to a form (check DOM in Elements tab)
5. Capture a screenshot showing the ActionCable subscription in the Network tab (WS connection) and a new comment appearing in real-time

## Stretch (Optional)

Add a delete button that removes a comment using `turbo_stream.remove` and broadcasts the removal to all connected clients.

## Time Estimate

22 minutes
