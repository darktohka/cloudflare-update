#!/bin/bash

set -uo pipefail

CONFIG_FILE="config/config.ini"
CACHE_FILE="config/cache.ini"

last_ipv4=
last_ipv6=
error_code=0

declare -A zone_ids

source "$CONFIG_FILE"

if [[ -f "$CACHE_FILE" ]]; then
  source "$CACHE_FILE"
fi

CLOUDFLARE_API="https://api.cloudflare.com/client/v4"
AUTH="Authorization: Bearer $api_token"

run_health_check() {
  if [[ -n "$healthcheck_url" ]]; then
    echo "Running health check."
    curl -s -o /dev/null --fail-with-body "$healthcheck_url"
  fi
}

A_ADDRESS=$(curl -4s --fail icanhazip.com)
AAAA_ADDRESS=$(curl -6s --fail icanhazip.com)

if [[ -z "$A_ADDRESS" ]] && [[ -z "$AAAA_ADDRESS" ]]; then
  echo "Not connected to the internet."
  return 0
fi

if [[ "$last_ipv4" = "$A_ADDRESS" ]] && [[ "$last_ipv6" = "$AAAA_ADDRESS" ]]; then
  echo "IP addresses have not changed."
  run_health_check
  exit 0
fi

if [[ -n "$A_ADDRESS" ]]; then
  echo "IPv4 address: $A_ADDRESS"
fi

if [[ -n "$AAAA_ADDRESS" ]]; then
  echo "IPv6 address: $AAAA_ADDRESS"
fi

exists_in_list() {
  list=$1
  value=$2

  for x in $list; do
    if [[ "$x" = "$value" ]]; then
      return 0
    fi
  done

  return 1
}

save_cache() {
  echo "last_ipv4=$A_ADDRESS
last_ipv6=$AAAA_ADDRESS
$(declare -p zone_ids)" > "$CACHE_FILE"
}

get_zone_id() {
  local zone_name="$1"

  if [[ ${zone_ids[$zone_name]+_} ]]; then
    zone_id="${zone_ids[$zone_name]}"
    return 0
  fi

  echo "Querying zone ID for $zone_name..."
  zone_id=$(curl -s --fail-with-body -H "$AUTH" "$CLOUDFLARE_API/zones?name=$zone_name&max_page=1" | jq -r 'first(.result[]).id')

  if [[ -z "$zone_id" ]]; then
    echo "The zone $zone_name does not exist."
    return 1
  fi

  if [[ $? -ne 0 ]]; then
    echo "Failed to get zone ID of $zone_name: $zone_id"
    return 2
  fi

  zone_ids+=(["$zone_name"]="$zone_id")
  return 0
}

for zone_name in $zones; do
  get_zone_id "$zone_name"
  zone_success="$?"

  if [[ $zone_success -ne 0 ]]; then
    error_code="$zone_success"
    continue
  fi

  echo "Querying DNS records for $zone_name..."
  dns_records=$(curl -s --fail-with-body -H "$AUTH" "$CLOUDFLARE_API/zones/$zone_id/dns_records?type=A,AAAA&max_page=5000" | jq -rc ".result[] | (.id, .name, .type, .content, .proxied, .ttl, .locked)")

  if [[ $? -ne 0 ]]; then
    echo "Failed to get DNS records of $zone_name: $dns_records"
    continue
  fi

  while read -r dns_id dns_name dns_type dns_content dns_proxied dns_ttl dns_locked dns_records < <(echo -e $dns_records); do
    if [[ -z "$dns_id" ]]; then
      break
    fi

    if exists_in_list "$skip_records" "$dns_name"; then
      echo "Skipping subdomain $dns_name: skipped in the config."
      continue
    fi

    if [[ "$dns_locked" = "true" ]]; then
      echo "Skipping locked subdomain $dns_name."
      continue
    fi

    if [[ "$dns_type" = "A" ]]; then
      if [[ -z "$A_ADDRESS" ]]; then
        echo "Skipping subdomain $dns_name due to unavailable IPv4 address."
        continue
      fi

      if [[ "$dns_content" = "$A_ADDRESS" ]]; then
        echo "Skipping subdomain $dns_name: correct IPv4 address has already been set."
        continue
      fi

      dns_content="$A_ADDRESS"
    elif [[ "$dns_type" = "AAAA" ]]; then
      if [[ -z "$AAAA_ADDRESS" ]]; then
        echo "Skipping subdomain $dns_name due to unavailable IPv6 address."
        continue
      fi

      if [[ "$dns_content" = "$AAAA_ADDRESS" ]]; then
        echo "Skipping subdomain $dns_name: correct IPv6 address has already been set."
        continue
      fi

      dns_content="$AAAA_ADDRESS"
    fi

    echo "Updating $dns_name $dns_type record to $dns_content (proxied: $dns_proxied, TTL: $dns_ttl)"
    record_data=$(jq -n --arg type "$dns_type" --arg name "$dns_name" --arg content "$dns_content" --argjson ttl "$dns_ttl" --argjson proxied "$dns_proxied" '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')
    update_response=$(curl -X PUT -s --fail-with-body -H "$AUTH" -H "Content-Type: application/json" --data "$record_data" "$CLOUDFLARE_API/zones/$zone_id/dns_records/$dns_id")

    if [[ $? -ne 0 ]]; then
      echo "Failed to update subdomain $dns_name: $update_response"
      error_code=3
    fi
  done
done

save_cache
run_health_check
exit $error_code
