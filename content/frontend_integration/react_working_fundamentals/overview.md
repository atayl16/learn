# React: Working fundamentals

## What It Is

React is a JavaScript library for building user interfaces through reusable components. Components manage their own state using hooks like `useState` and `useEffect`, rendering UI based on that state. When integrated with Rails, React handles complex client-side interactions while Rails serves data via JSON APIs or renders React components server-side using gems like react-rails.

## Why It Matters

Some UIs demand rich client-side interactivity that server-rendered approaches struggle with: real-time collaborative editors, complex data visualizations, or dashboards with heavy local state. React excels at these scenarios by managing component state and efficiently updating the DOM. For Rails apps, React provides an escape hatch when Hotwire's server-driven model becomes limiting, while still leveraging Rails for authentication, authorization, and business logic.

## When to Use

- Dashboards with complex filtering, sorting, and client-side calculations across large datasets
- Forms with dynamic fields that add/remove based on user input (e.g., invoice line items)
- Data visualizations requiring D3.js or Chart.js with interactive tooltips and live updates
- Single-page admin panels where full-page navigation would disrupt workflow
- Real-time collaboration features like shared document editing or live chat

## Three Common Pitfalls

1. **Prop drilling through many layers:** Passing props down 4-5 levels makes components brittle. Use Context API or a state library like Zustand to share state across the tree without threading props.
2. **Fetching in useEffect without cleanup:** Async requests that complete after unmount cause "Can't perform a React state update on an unmounted component" warnings. Always cancel requests or check a mounted flag in the cleanup function.
3. **Missing dependency arrays in useEffect:** Omitting dependencies causes stale closures where the effect uses old state values. Add all variables from component scope to the array or use a linter rule to catch this.

---

## Components and Props

Components are JavaScript functions that return JSX. Props pass data from parent to child:

```javascript
// app/javascript/components/UserCard.jsx
export default function UserCard({ name, email }) {
  return (
    <div className="card">
      <h3>{name}</h3>
      <p>{email}</p>
    </div>
  )
}

```

Render it with data:

```javascript
import UserCard from './UserCard'

function App() {
  return <UserCard name="Alice" email="alice@example.com" />
}

```

Props are read-only. To change data, lift state up to a parent component.

---

## useState: Managing Local State

`useState` declares state that persists across renders:

```javascript
import { useState } from 'react'

export default function Counter() {
  const [count, setCount] = useState(0)

  return (
    <div>
      <p>Count: {count}</p>
      <button onClick={() => setCount(count + 1)}>Increment</button>
    </div>
  )
}

```

Updating state triggers a re-render. Never mutate state directly; always call the setter function.

---

## useEffect: Side Effects and Data Fetching

`useEffect` runs after render for side effects like fetching data:

```javascript
import { useState, useEffect } from 'react'

export default function PostList() {
  const [posts, setPosts] = useState([])

  useEffect(() => {
    fetch('/api/posts')
      .then(response => response.json())
      .then(data => setPosts(data))
  }, []) // Empty array means run once on mount

  return (
    <ul>
      {posts.map(post => <li key={post.id}>{post.title}</li>)}
    </ul>
  )
}

```

Add cleanup to avoid memory leaks:

```javascript
useEffect(() => {
  const controller = new AbortController()

  fetch('/api/posts', { signal: controller.signal })
    .then(response => response.json())
    .then(data => setPosts(data))
    .catch(error => {
      if (error.name !== 'AbortError') console.error(error)
    })

  return () => controller.abort() // Cleanup on unmount
}, [])

```

---

## Fetching Data with React Query

React Query simplifies data fetching, caching, and synchronization:

```javascript
import { useQuery } from '@tanstack/react-query'

export default function PostList() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['posts'],
    queryFn: () => fetch('/api/posts').then(res => res.json())
  })

  if (isLoading) return <p>Loading...</p>
  if (error) return <p>Error: {error.message}</p>

  return (
    <ul>
      {data.map(post => <li key={post.id}>{post.title}</li>)}
    </ul>
  )
}

```

React Query handles caching, background refetching, and deduplication automatically. Install with `npm install @tanstack/react-query`.

---

## Forms with Controlled Inputs

Controlled inputs store value in React state:

```javascript
import { useState } from 'react'

export default function PostForm() {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')

  const handleSubmit = (e) => {
    e.preventDefault()
    fetch('/api/posts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, body })
    })
  }

  return (
    <form onSubmit={handleSubmit}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} />
      <textarea value={body} onChange={(e) => setBody(e.target.value)} />
      <button type="submit">Create</button>
    </form>
  )
}

```

Every keystroke updates state and re-renders. For large forms, consider uncontrolled inputs with refs.

---

## Integrating with Rails: react-rails Gem

The `react-rails` gem renders React components in Rails views:

```bash
bundle add react-rails
rails webpacker:install:react
rails generate react:install

```

Create a component:

```javascript
// app/javascript/components/HelloWorld.jsx
export default function HelloWorld({ name }) {
  return <h1>Hello, {name}!</h1>
}

```

Render in a view:

```erb
<%= react_component("HelloWorld", { name: "World" }) %>

```

This server-renders React components for initial page load, then hydrates client-side.

---

## Integrating with Rails: JSON API Approach

Separate frontend and backend: Rails serves JSON, React consumes it:

```ruby
# app/controllers/api/posts_controller.rb
class Api::PostsController < ApplicationController
  def index
    render json: Post.all
  end
end

```

Fetch from React:

```javascript
useEffect(() => {
  fetch('/api/posts')
    .then(res => res.json())
    .then(setPosts)
}, [])

```

Include CSRF token for POST requests:

```javascript
const csrfToken = document.querySelector('[name=csrf-token]').content

fetch('/api/posts', {
  method: 'POST',
  headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
  body: JSON.stringify({ title: 'New Post' })
})

```

---

## Trade-offs Box

- **Advantage:** React handles complex client-side interactions and state management that Hotwire struggles with, leveraging a vast ecosystem of libraries.
- **Cost:** Requires build tooling (Webpack, Vite), increases bundle size, and adds complexity compared to server-rendered Hotwire approaches.
- **When to skip:** Simple CRUD apps or admin panels with minimal interactivity benefit more from Hotwire's simplicity and Rails conventions.

---

## Debugging Checklist

When things go wrong, check:

1. Open React DevTools extension to inspect component state, props, and hook values in real time
2. Check Console for "Can't perform a React state update on an unmounted component" warnings indicating missing cleanup in useEffect
3. Verify CSRF token is included in POST/PUT/DELETE requests (check Network tab request headers)
4. Look for missing `key` props in lists, which cause incorrect re-renders and lost state
5. Inspect Network tab for failed API requests and confirm Rails routes are configured to respond with JSON
6. Add `console.log` in useEffect to confirm it's running and check the dependency array for stale closures

---

## One-Minute Recap

- React builds UIs with components that manage state using hooks like useState and useEffect
- Props pass data down the component tree; state updates trigger re-renders
- React Query simplifies data fetching with automatic caching and background refetching
- Controlled inputs store form values in React state, syncing input value with state on every keystroke
- Integrate with Rails via react-rails gem for server rendering or build a JSON API for a fully decoupled frontend
