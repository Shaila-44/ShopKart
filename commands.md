# Commands to Run

### Step 1: Start the containers
```bash
docker compose up -d --build
```

### Step 2: Set up the database
```bash
docker compose exec backend bin/rails db:migrate
docker compose exec backend bin/rails db:seed
```

### Step 3: Open the app
```bash
open http://localhost:5173
```
