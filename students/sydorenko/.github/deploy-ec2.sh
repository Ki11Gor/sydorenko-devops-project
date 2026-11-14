#!/bin/bash
set -euo pipefail

: "${EC2_INSTANCE_ID:?Missing instance ID}"
: "${EC2_IP:?Missing instance address}"
: "${SECURITY_GROUP_ID:?Missing security group ID}"
: "${EC2_SSH_KEY_B64:?Set the EC2_SSH_KEY_B64 secret}"
: "${DOCKER_USERNAME:?Set the DOCKER_USERNAME secret}"
: "${IMAGE_DIGEST:?Missing the Docker Hub image digest}"
[[ "$DOCKER_USERNAME" =~ ^[a-z0-9]+([_-][a-z0-9]+)*$ ]]
[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]
image="$DOCKER_USERNAME/study-planner@$IMAGE_DIGEST"

umask 077
ssh_dir=$(mktemp -d)
rule_id=''

cleanup() {
  result=$?
  trap - EXIT
  rm -rf -- "$ssh_dir"
  if [[ -n "$rule_id" ]]; then
    if ! aws ec2 revoke-security-group-ingress --group-id "$SECURITY_GROUP_ID" \
      --security-group-rule-ids "$rule_id" >/dev/null; then
      printf 'Remove temporary SSH rule %s in AWS.\n' "$rule_id" >&2
      exit 1
    fi
  fi
  exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$EC2_SSH_KEY_B64" | base64 --decode > "$ssh_dir/key"
ssh-keygen -y -f "$ssh_dir/key" </dev/null >/dev/null

aws ec2 wait instance-running --instance-ids "$EC2_INSTANCE_ID"
host_key=''
for ((attempt = 1; attempt <= 30; attempt++)); do
  console=$(aws ec2 get-console-output --instance-id "$EC2_INSTANCE_ID" --latest \
    --query Output --output text)
  host_key=$(printf '%s\n' "$console" | sed -nE 's/.*STUDY_PLANNER_SSH_KEY (ssh-ed25519 [A-Za-z0-9+/=]+).*/\1/p' | tail -n 1)
  if [[ -n "$host_key" ]]; then
    break
  fi
  sleep 10
done
: "${host_key:?EC2 bootstrap did not publish its SSH host key to the AWS console}"
printf '%s %s\n' "$EC2_IP" "$host_key" > "$ssh_dir/known_hosts"

runner_ip=$(curl -4 -fsS --retry 3 --max-time 10 https://checkip.amazonaws.com/)
[[ "$runner_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
rule_id=$(aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$runner_ip/32,Description=GitHubActions-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT}]" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
[[ "$rule_id" =~ ^sgr-[a-f0-9]+$ ]]

ssh -i "$ssh_dir/key" -o UserKnownHostsFile="$ssh_dir/known_hosts" \
  -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o BatchMode=yes \
  -o ConnectTimeout=10 -o ConnectionAttempts=5 "ubuntu@$EC2_IP" "bash -se -- '$image'" <<'REMOTE'
set -euo pipefail
image=$1
name=study-planner

docker() {
  sudo -n docker "$@"
}

start_container() {
  docker run -d --name "$name" --restart unless-stopped -p 3000:3000 "$1" >/dev/null
}

docker pull "$image"
previous_image=$(docker container inspect --format '{{.Image}}' "$name" 2>/dev/null || true)
if [[ -n "$previous_image" ]]; then
  docker rm -f "$name" >/dev/null
fi

if start_container "$image" \
  && health=$(curl -fsS --retry 8 --retry-all-errors --max-time 3 http://127.0.0.1:3000/health) \
  && [[ "$health" == '{"status":"ok"}' ]]; then
  printf 'EC2 health check passed.\n'
else
  docker logs "$name" >&2 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
  if [[ -n "$previous_image" ]]; then
    start_container "$previous_image"
  fi
  exit 1
fi
REMOTE
