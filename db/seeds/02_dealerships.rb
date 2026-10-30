[
  [ 1, "Londinium Motors", "Europe/London" ],
  [ 2, "Manhattan Auto Care", "America/New_York" ]
].each do |number, name, time_zone|
  SeedSupport.upsert!(Dealership, SeedSupport.uuid(0x20, number), name: name, time_zone: time_zone)
end
