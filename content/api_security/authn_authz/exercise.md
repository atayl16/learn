# Exercise: Authentication & Authorization with Pundit

## Objective

Implement token-based authentication and Pundit authorization for an API endpoint, ensuring users can only update their own resources.

## Task

You're securing a task management API. Add JWT-based authentication to `ApplicationController`, create a `TaskPolicy` allowing users to update only their own tasks, and implement a policy scope so `GET /api/tasks` returns only the current user's tasks. Test with multiple users.

1. Add `jwt` and `pundit` gems to Gemfile and run `bundle install`
2. Generate Pundit initializer: `rails g pundit:install`
3. Implement `authenticate_user!` in `ApplicationController` using JWT tokens
4. Create `TaskPolicy` with `update?` returning true only if `record.user_id == user.id`
5. Create `TaskPolicy::Scope` filtering tasks to `scope.where(user_id: user.id)`
6. Apply `authorize @task` in `TasksController#update` and `policy_scope(Task)` in `index`
7. Test with curl, verifying 403 when updating another user's task

## Acceptance Criteria

- [ ] `ApplicationController` authenticates via `Authorization: Bearer <token>` header
- [ ] `TaskPolicy#update?` returns true only for task owner
- [ ] `TaskPolicy::Scope#resolve` returns only current user's tasks
- [ ] `PATCH /api/tasks/:id` returns 403 if user doesn't own the task
- [ ] `GET /api/tasks` returns only current user's tasks
- [ ] Missing or invalid token returns 401 Unauthorized

## Verification Steps

1. Generate two JWT tokens for two different users: `user1_token` and `user2_token`
2. Create tasks belonging to user1 and user2
3. Execute `curl -H "Authorization: Bearer $user1_token" http://localhost:3000/api/tasks` and verify only user1's tasks returned
4. Execute `curl -X PATCH -H "Authorization: Bearer $user1_token" http://localhost:3000/api/tasks/{user1_task_id} -d '{"title": "Updated"}'` and verify 200 OK
5. Execute `curl -X PATCH -H "Authorization: Bearer $user1_token" http://localhost:3000/api/tasks/{user2_task_id} -d '{"title": "Hacked"}'` and verify 403 Forbidden
6. Execute `curl http://localhost:3000/api/tasks` (no token) and verify 401 Unauthorized
7. Run policy specs: `rspec spec/policies/task_policy_spec.rb` and confirm all pass

## Stretch (Optional)

Add an `admin` role to users and update `TaskPolicy#destroy?` to allow admins to delete any task, then test that admins can delete others' tasks while regular users cannot.

## Time Estimate

25 minutes
