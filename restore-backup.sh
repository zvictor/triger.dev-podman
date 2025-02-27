#!/usr/bin/env bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Clean up previous environment
echo -e "${BLUE}Step 1: Cleaning up previous environment...${NC}"
podman-compose down -v

# Step 2: Find latest valid backup (non-zero size)
echo -e "${BLUE}Step 2: Finding latest valid backup...${NC}"
LATEST_BACKUP=$(find ./backups -name "postgres_backup_*.sql" -type f -size +1k | sort -r | head -n1)

if [ -z "$LATEST_BACKUP" ]; then
  echo -e "${RED}Error: No valid backup files found in ./backups${NC}"
  exit 1
fi

echo -e "${GREEN}Using backup file: ${LATEST_BACKUP}${NC}"

# Step 3: Start only the PostgreSQL container
echo -e "${BLUE}Step 3: Starting PostgreSQL container...${NC}"
podman-compose up -d postgres

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
sleep 5
RETRIES=10
while [ $RETRIES -gt 0 ]; do
  if podman exec $(podman ps -qf name=postgres) pg_isready -U postgres; then
    echo -e "${GREEN}PostgreSQL is ready.${NC}"
    break
  fi
  echo -e "${YELLOW}Waiting for PostgreSQL to start... ($RETRIES retries left)${NC}"
  sleep 3
  RETRIES=$((RETRIES-1))
done

if [ $RETRIES -eq 0 ]; then
  echo -e "${RED}PostgreSQL did not start properly. Exiting.${NC}"
  exit 1
fi

# Step 4: Restore the backup
echo -e "${BLUE}Step 4: Restoring backup...${NC}"
podman cp "${LATEST_BACKUP}" $(podman ps -qf name=postgres):/tmp/backup.sql
podman exec $(podman ps -qf name=postgres) psql -U postgres -f /tmp/backup.sql

# Step 5: Create a temporary .env file with recovery settings
echo -e "${BLUE}Step 5: Creating temporary environment with recovery settings...${NC}"
cp .env .env.recovery
echo "SKIP_DATABASE_INIT=1" >> .env.recovery
echo "DISABLE_MIGRATIONS=1" >> .env.recovery

# Step 6: Start all remaining services with the recovery environment
echo -e "${BLUE}Step 6: Starting all remaining services...${NC}"
podman-compose --env-file .env.recovery up -d

# Step 7: Verify running services and data
echo -e "${BLUE}Step 7: Verifying services...${NC}"
sleep 10 # Give services time to start
echo -e "${YELLOW}Database tables:${NC}"
podman exec $(podman ps -qf name=postgres) psql -U postgres -c "\dt"
echo -e "${YELLOW}Webapp logs:${NC}"
podman logs $(podman ps -qf name=webapp) | tail -20

# Cleanup temp file
rm .env.recovery

echo -e "${GREEN}Restoration complete! Services are running with restored data.${NC}"