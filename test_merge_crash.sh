#!/bin/bash
./GitTracker &
PID=$!
sleep 2
kill $PID
