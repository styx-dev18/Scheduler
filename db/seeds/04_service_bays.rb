[
  [ 1, 1, "Bay G1", "general" ],
  [ 2, 1, "Bay L1", "lift" ],
  [ 3, 1, "Bay L2", "lift" ],
  [ 4, 1, "Bay A1", "alignment" ],
  [ 5, 2, "Bay G1", "general" ],
  [ 6, 2, "Bay G2", "general" ],
  [ 7, 2, "Bay L1", "lift" ],
  [ 8, 2, "Bay A1", "alignment" ]
].each do |number, dealership_number, name, bay_type|
  SeedSupport.upsert!(
    ServiceBay,
    SeedSupport.uuid(0x40, number),
    dealership_id: SeedSupport.uuid(0x20, dealership_number), name: name, bay_type: bay_type, active: true
  )
end
