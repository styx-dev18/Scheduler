# Error catalogue

| Code | Status | Title | Example |
|---|---|---|---|
| `VALIDATION_ERROR` | 422 | Validation failed | A required field is missing or malformed in the request body. |
| `NOT_FOUND` | 404 | Resource not found | The referenced customer, vehicle, service type or dealership does not exist. |
| `APPOINTMENT_NOT_FOUND` | 404 | Appointment not found | GET /api/v1/appointments/{id} with an id that does not exist. |
| `CONCURRENT_MODIFICATION` | 409 | Concurrent modification | Two requests update the same appointment at the same moment. |
| `INTERNAL_ERROR` | 500 | Internal server error | An unexpected failure occurred while processing the request. |
| `START_TIME_IN_PAST` | 422 | Start time is in the past | Booking with a start time earlier than the current time. |
| `START_TIME_NOT_ON_SLOT_GRID` | 422 | Start time is not on the slot grid | Booking at 09:10 when slots start every 30 minutes. |
| `VEHICLE_OWNERSHIP_MISMATCH` | 422 | Vehicle ownership mismatch | The vehicle does not belong to the given customer. |
| `OUTSIDE_OPENING_HOURS` | 422 | Outside opening hours | Booking a 2 hour service starting 17:00 at a dealership that closes at 18:00. |
| `DEALERSHIP_CLOSED` | 422 | Dealership closed | Booking on a Sunday when the dealership is closed. |
| `VEHICLE_ALREADY_BOOKED` | 409 | Vehicle already booked | The vehicle already has an appointment overlapping the requested time. |
| `NO_BAY` | 409 | No service bay available | Every service bay is occupied during the requested interval. |
| `NO_TECHNICIAN` | 409 | No technician available | No qualified technician is free for the whole requested interval. |
| `NO_CAPACITY` | 409 | No capacity available | No bay and technician pair is free for the requested interval. |
| `IDEMPOTENCY_KEY_REUSED` | 422 | Idempotency key reused | The same Idempotency-Key is sent with a different request body. |
| `IDEMPOTENCY_KEY_IN_PROGRESS` | 409 | Idempotency key in progress | A request with the same Idempotency-Key is still being processed. |
| `INVALID_STATUS_TRANSITION` | 409 | Invalid status transition | Confirming an appointment that is already cancelled. |
| `CANCELLATION_WINDOW_CLOSED` | 422 | Cancellation window closed | Cancelling an appointment too close to its start time. |
| `UNAUTHORIZED` | 401 | Unauthorized | The metrics endpoint is called with a missing or invalid bearer token. |
| `RATE_LIMITED` | 429 | Too many requests | More requests than the per-client limit within the throttle window. |
| `REQUEST_TIMEOUT` | 504 | Request timed out | The request exceeded the server-side time limit. |
| `SERVICE_UNAVAILABLE` | 503 | Service unavailable | A dependency such as the database is temporarily unreachable. |
