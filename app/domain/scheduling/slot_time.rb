module Scheduling
  SlotTime = Data.define(:starts_at, :slot_minutes) do
    def self.aligned?(time, slot_minutes)
      time.to_r % (slot_minutes * 60) == 0
    end

    def initialize(starts_at:, slot_minutes:)
      unless slot_minutes.is_a?(Integer) && slot_minutes.positive?
        raise ArgumentError, "slot_minutes must be a positive Integer"
      end
      raise ArgumentError, "starts_at is not on the slot grid" unless self.class.aligned?(starts_at, slot_minutes)

      super
    end
  end
end
