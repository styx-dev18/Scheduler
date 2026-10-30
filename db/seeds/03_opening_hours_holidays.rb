hours = { 1 => [ "08:00", "17:00" ], 2 => [ "08:00", "17:00" ] }
holidays = { 1 => [ Date.new(2026, 12, 25), "Christmas Day" ], 2 => [ Date.new(2026, 7, 4), "Independence Day" ] }

hours.each do |dealership_number, (opens_at, closes_at)|
  dealership_id = SeedSupport.uuid(0x20, dealership_number)
  (1..5).each do |day|
    SeedSupport.upsert!(
      DealershipOpeningHour,
      SeedSupport.uuid(0x30, (dealership_number * 10) + day),
      dealership_id: dealership_id, day_of_week: day, opens_at: opens_at, closes_at: closes_at
    )
  end
end

holidays.each do |dealership_number, (holiday_on, name)|
  SeedSupport.upsert!(
    DealershipHoliday,
    SeedSupport.uuid(0x31, dealership_number),
    dealership_id: SeedSupport.uuid(0x20, dealership_number), holiday_on: holiday_on, name: name
  )
end
