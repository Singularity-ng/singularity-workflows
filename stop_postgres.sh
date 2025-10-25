#!/bin/bash
# Stop ex_pgflow PostgreSQL instance
if [ -d ".postgres_data" ]; then
    echo "Stopping ex_pgflow PostgreSQL..."
    pg_ctl -D .postgres_data stop
    echo "PostgreSQL stopped"
else
    echo "No ex_pgflow PostgreSQL instance found"
fi
