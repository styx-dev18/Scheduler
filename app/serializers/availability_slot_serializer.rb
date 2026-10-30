class AvailabilitySlotSerializer
  include Alba::Resource

  attribute(:start_at) { |slot| slot.starts_at.utc.iso8601 }
  attribute(:local_start_at) { |slot| slot.starts_at.in_time_zone(params[:time_zone]).iso8601 }
end
