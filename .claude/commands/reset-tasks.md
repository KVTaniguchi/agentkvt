Reset stuck or failed objective tasks on the production server.

1. Run: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'cd ~/Development/agentkvt && ./bin/agentkvt_reset_objective_tasks.sh'`
2. Report how many tasks were reset and their prior states.
3. If the script is not present on the server, fall back to: `ssh familyagent@taniguchis-macbook-pro.tail82812d.ts.net 'cd ~/Development/agentkvt/server && RAILS_ENV=production bundle exec rails runner "ObjectiveTask.where(status: [\"failed\",\"running\"]).update_all(status: \"pending\")"'`
