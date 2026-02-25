#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"

echo "Starting full demo cleanup in ${AWS_REGION} using profile ${AWS_PROFILE}"

bash scripts/09_destroy_fargate_web_interface.sh
bash scripts/10_destroy_neptune_data_and_runner.sh

echo "All demo cleanup scripts completed."
