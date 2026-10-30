module Scheduling
  class OpeningHoursPolicy
    def initialize(zone:, opening_hours:, holidays:)
      @zone = zone
      @opening_hours = opening_hours
      @holidays = holidays
    end

    def evaluate(interval)
      local_start = @zone.utc_to_local(interval.starts_at)
      local_end = @zone.utc_to_local(interval.ends_at)
      start_date = local_start.to_date
      windows = @opening_hours.select { |hours| hours[:day_of_week] == start_date.wday }

      return :closed if @holidays.include?(start_date) || windows.empty?
      return :outside_hours if local_end.to_date != start_date

      start_seconds = seconds_of_day(local_start)
      end_seconds = seconds_of_day(local_end)
      fits = windows.any? do |hours|
        parse(hours[:opens_at]) <= start_seconds && end_seconds <= parse(hours[:closes_at])
      end

      fits ? :open : :outside_hours
    end

    private

    def seconds_of_day(time)
      time.hour * 3600 + time.min * 60 + time.sec
    end

    def parse(text)
      hours, minutes = text.split(":").map(&:to_i)
      hours * 3600 + minutes * 60
    end
  end
end
