# Exercise: React: Working fundamentals

## Objective

Build a React component that fetches posts from a Rails API, displays them in a list, and allows creating new posts with a controlled form.

## Task

Set up a React app integrated with a Rails backend:

1. **Rails API endpoint:** Create a `PostsController` with `index` and `create` actions that respond to JSON. The `index` action should return all posts as JSON. The `create` action should accept `title` and `body` parameters, create a `Post`, and return the created record as JSON.

2. **Fetch and display posts:** Create a React component `PostList` that uses `useEffect` to fetch posts from `/api/posts` on mount. Display them in an unordered list. Show "Loading..." while the request is in flight and handle errors by displaying an error message.

3. **Controlled form:** Add a form with inputs for title and body. Use `useState` to manage form values. On submit, POST to `/api/posts` with the CSRF token in the request headers. After successful creation, refetch the posts to show the new entry.

4. **Cleanup:** Add an AbortController to the fetch request in `useEffect` and abort it in the cleanup function to prevent state updates on unmounted components.

5. **React Query (optional upgrade):** Replace the manual `useEffect` and fetch logic with `useQuery` for fetching and `useMutation` for creating posts. This simplifies loading states and automatic refetching after mutations.

## Acceptance Criteria

- [ ] The Rails API returns JSON for GET `/api/posts` and POST `/api/posts` with correct status codes (200, 201)
- [ ] The React component displays a loading message while fetching posts on initial render
- [ ] Posts appear in a list after the fetch completes, showing title and body
- [ ] The form inputs update in real time as the user types (controlled components)
- [ ] Submitting the form creates a new post and refreshes the list without a page reload
- [ ] The AbortController cleanup prevents console warnings when navigating away during a fetch

## Verification Steps

1. Run `rails server` and navigate to the page with the React component
2. Open DevTools Network tab and confirm a GET request to `/api/posts` on page load
3. Type in the form fields and verify React DevTools shows state updating with each keystroke
4. Submit the form and verify a POST request with CSRF token in the headers (inspect Request Headers)
5. Confirm the new post appears in the list immediately after creation
6. Navigate away quickly after submitting and check Console for no unmounted component warnings

## Stretch (Optional)

Add delete functionality: display a "Delete" button next to each post that sends a DELETE request to `/api/posts/:id` and removes the post from the list using React Query's `useMutation` with automatic cache invalidation.

## Time Estimate

24 minutes
