#!/bin/bash
# Local webhook simulation

curl -X POST http://127.0.0.1:8765 \
  -H "Content-Type: application/json" \
  -d '{
    "agentkvt": "run_task_search",
    "task_id": "c91d99e9-1b7b-4940-bb1d-dba12e6958f4",
    "objective_id": "b0a503d7-ac5a-4ed2-8837-617896dcbc7d",
    "description": "Find the strongest recommendations and alternatives for Universal Studios.",
    "objective_goal": "Plan our family Universal Studios Orlando trip."
  }'

echo "Webhook sent."
