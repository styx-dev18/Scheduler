module Scheduling
  module AssignmentStrategies
    class LeastLoaded
      def choose(bays:, technicians:, interval:, loads: {})
        return nil if bays.empty? || technicians.empty?

        Assignment.new(
          bay_id: bays.min,
          technician_id: technicians.min_by { |id| [ loads.fetch(id, 0), id ] }
        )
      end
    end
  end
end
