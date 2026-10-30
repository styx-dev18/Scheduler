#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BASE_URL="${BASE_URL:-http://localhost:3000}"
CURRENT_STEP="setup"

fail() {
  echo "FAIL: ${CURRENT_STEP}" >&2
  exit 1
}
trap fail ERR

wait_for_web() {
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fs "${BASE_URL}/up" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

fetch_status() {
  curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/appointments/${APPOINTMENT_ID}"
}

check_retrievable() {
  CURRENT_STEP="$1"
  wait_for_web
  [ "$(fetch_status)" = "200" ]
  echo "ok: ${CURRENT_STEP}"
}

CURRENT_STEP="start stack"
docker compose up -d --build --wait
wait_for_web

CURRENT_STEP="pick bookable payload"
PAYLOAD="$(docker compose exec -T web bin/rails runner - <<'RUBY'
dealership_service_type = DealershipServiceType.includes(:dealership, :service_type).first
dealership = dealership_service_type.dealership
service_type = dealership_service_type.service_type
vehicle = Vehicle.joins(:customer).first
finder = Availability::DaySlots.new
zone = ActiveSupport::TimeZone[dealership.time_zone]
first_date = zone.now.to_date + 7
start_at = nil
(0..30).each do |offset|
  slots = finder.call(dealership: dealership, service_type: service_type, date: first_date + offset)
  next if slots.empty?

  start_at = slots.first.starts_at.utc.iso8601
  break
end
abort("no bookable slot found") if start_at.nil?
puts({
  customer_id: vehicle.customer_id,
  vehicle_id: vehicle.id,
  service_type_id: service_type.id,
  dealership_id: dealership.id,
  start_at: start_at
}.to_json)
RUBY
)"
PAYLOAD="$(printf '%s\n' "${PAYLOAD}" | grep '^{' | tail -n 1)"

CURRENT_STEP="create appointment"
RESPONSE="$(curl -fs -X POST "${BASE_URL}/api/v1/appointments" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: persistence-check-$(date +%s)-$$" \
  -d "${PAYLOAD}")"
APPOINTMENT_ID="$(printf '%s' "${RESPONSE}" | grep -o '"data":{"id":"[^"]*"' | head -n 1 | cut -d'"' -f6)"
[ -n "${APPOINTMENT_ID}" ]
check_retrievable "after creation"

CURRENT_STEP="web restart"
docker compose restart web
check_retrievable "after web restart"

CURRENT_STEP="db restart"
docker compose restart db
check_retrievable "after db restart"

CURRENT_STEP="down and up"
docker compose down
docker compose up -d --wait
check_retrievable "after down and up"

trap - ERR
echo "PASS: appointment ${APPOINTMENT_ID} survived every step"
