#!/bin/bash

echo "🔨 Starting the hammer... Press Ctrl+C to stop."

start_time=$(date +%s)
attempts=0

while true; do
  for i in 1 2 3; do
    echo "----------------------------------------------------"
    echo "Attempt: $((attempts + 1)) - Total Time: $((($(date +%s) - start_time) / 60))m $((($(date +%s) - start_time) % 60))s"
    echo "Trying Availability Domain $i..."
    echo "----------------------------------------------------"
    
    ((attempts++))
    
    # Try to apply with the specific AD number
    terraform apply -auto-approve -var="ad_number=$i"
    
    # Check if Terraform succeeded (Exit code 0)
    if [ $? -eq 0 ]; then
      end_time=$(date +%s)
      duration=$((end_time - start_time))
      echo "✅ SUCCESS! Managed to provision in AD-$i"
      echo "----------------------------------------------------"
      echo "📊 Summary:"
      echo "  Start Time:  $(date -d @$start_time)"
      echo "  End Time:    $(date -d @$end_time)"
      echo "  Duration:    $((duration / 60))m $((duration % 60))s"
      echo "  Attempts:    $attempts"
      echo "----------------------------------------------------"
      exit 0
    fi
    
    echo "❌ AD-$i is full or failed. Waiting 10 seconds before next AD..."
    sleep 10
  done
  
  echo "⚠️ All ADs full. Sleeping 60 seconds before retrying loop..."
  sleep 60
done