[
  [ 1, 1, 1 ],
  [ 2, 1, 2 ],
  [ 3, 1, 3 ],
  [ 4, 2, 1 ],
  [ 5, 2, 2 ]
].each do |number, dealership_number, service_type_number|
  SeedSupport.upsert!(
    DealershipServiceType,
    SeedSupport.uuid(0x51, number),
    dealership_id: SeedSupport.uuid(0x20, dealership_number),
    service_type_id: SeedSupport.uuid(0x50, service_type_number)
  )
end
