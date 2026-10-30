module Availability
  class Alternatives
    def initialize(day_slots: Availability::DaySlots.new, count: Integer(ENV.fetch("ALTERNATIVE_SLOTS_COUNT", "3")))
      @day_slots = day_slots
      @count = count
    end

    def call(dealership:, service_type:, interval:)
      date = interval.starts_at.in_time_zone(dealership.time_zone).to_date
      @day_slots.call(dealership:, service_type:, date:)
        .reject { |slot| slot.starts_at == interval.starts_at }
        .sort_by { |slot| [ (slot.starts_at - interval.starts_at).abs, slot.starts_at ] }
        .first(@count)
        .map { |slot| slot.starts_at.utc.iso8601 }
    end
  end
end
