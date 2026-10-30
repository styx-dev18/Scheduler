technicians = [
  [ 1, 1, "Alice Archer", [ 1, 2 ] ],
  [ 2, 1, "Bob Brewer", [ 1, 3 ] ],
  [ 3, 1, "Carol Chandler", [ 1 ] ],
  [ 4, 2, "Dan Dalton", [ 1, 2, 3 ] ],
  [ 5, 2, "Erin Eastwood", [ 1 ] ],
  [ 6, 2, "Frank Fowler", [ 1, 3 ] ]
]

technicians.each do |number, dealership_number, name, qualification_numbers|
  technician_id = SeedSupport.uuid(0x60, number)
  SeedSupport.upsert!(
    Technician, technician_id, dealership_id: SeedSupport.uuid(0x20, dealership_number), name: name, active: true
  )

  qualification_numbers.each do |qualification_number|
    SeedSupport.upsert!(
      TechnicianQualification,
      SeedSupport.uuid(0x61, (number * 10) + qualification_number),
      technician_id: technician_id, qualification_id: SeedSupport.uuid(0x10, qualification_number)
    )
  end

  starts_at, ends_at = number.odd? ? [ "08:00", "16:00" ] : [ "09:00", "17:00" ]
  (1..5).each do |day|
    SeedSupport.upsert!(
      TechnicianShift,
      SeedSupport.uuid(0x62, (number * 10) + day),
      technician_id: technician_id, day_of_week: day, starts_at: starts_at, ends_at: ends_at
    )
  end
end
