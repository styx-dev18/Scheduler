module Scheduling
  TimeInterval = Data.define(:starts_at, :ends_at) do
    def self.from_slot(slot_time, duration_minutes:)
      unless duration_minutes.is_a?(Numeric) && duration_minutes.positive?
        raise ArgumentError, "duration_minutes must be positive"
      end

      new(starts_at: slot_time.starts_at, ends_at: slot_time.starts_at + duration_minutes * 60)
    end

    def initialize(starts_at:, ends_at:)
      raise ArgumentError, "starts_at and ends_at are required" if starts_at.nil? || ends_at.nil?
      raise ArgumentError, "ends_at must be after starts_at" if ends_at <= starts_at

      super
    end

    def overlaps?(other)
      starts_at < other.ends_at && other.starts_at < ends_at
    end

    def cover?(other)
      starts_at <= other.starts_at && other.ends_at <= ends_at
    end

    def duration
      ends_at - starts_at
    end
  end
end
