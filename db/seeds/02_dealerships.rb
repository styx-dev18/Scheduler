[
  [ 1, "Hoan Kiem Motors", "Asia/Ho_Chi_Minh" ],
  [ 2, "Saigon Auto Care", "Asia/Ho_Chi_Minh" ]
].each do |number, name, time_zone|
  SeedSupport.upsert!(Dealership, SeedSupport.uuid(0x20, number), name: name, time_zone: time_zone)
end
