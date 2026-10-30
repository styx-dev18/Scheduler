class DealershipSerializer
  include Alba::Resource

  attributes :id, :name, :time_zone

  attribute :opening_hours do |dealership|
    dealership.opening_hours.sort_by { |hour| [ hour.day_of_week, hour.opens_at ] }.map do |hour|
      {
        day_of_week: hour.day_of_week,
        opens_at: hour.opens_at.strftime("%H:%M"),
        closes_at: hour.closes_at.strftime("%H:%M")
      }
    end
  end
end
