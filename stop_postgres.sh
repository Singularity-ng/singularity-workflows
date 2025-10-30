#!/bin/bash
# Stop quantum_flow PostgreSQL instance
if [ -d ".postgres_data" ]; then
    echo "Stopping quantum_flow PostgreSQL..."
    pg_ctl -D .postgres_data stop
    echo "PostgreSQL stopped"
else
    echo "No quantum_flow PostgreSQL instance found"
fi
