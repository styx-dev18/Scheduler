[
  [ 1, "Oil Change", 30, 1, "general" ],
  [ 2, "Full Service", 120, 2, "lift" ],
  [ 3, "Wheel Alignment", 60, 3, "alignment" ]
].each do |number, name, duration_minutes, qualification_number, bay_type|
  SeedSupport.upsert!(
    ServiceType,
    SeedSupport.uuid(0x50, number),
    name: name,
    duration_minutes: duration_minutes,
    required_qualification_id: SeedSupport.uuid(0x10, qualification_number),
    required_bay_type: bay_type
  )
end
