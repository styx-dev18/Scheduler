class Current < ActiveSupport::CurrentAttributes
  attribute :request_id, :trace_id, :appointment_id
end
