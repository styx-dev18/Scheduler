[
  [ 1, "Grace Hopper", "grace.hopper@example.com", "+44 20 7946 0001", "1HGCM82633A000001", "Honda", "Accord", 2019, "GH19 ACC" ],
  [ 2, "Alan Turing", "alan.turing@example.com", "+44 20 7946 0002", "WVWZZZ1JZ3W000002", "Volkswagen", "Golf", 2021, "AT21 VWG" ],
  [ 3, "Katherine Johnson", "katherine.johnson@example.com", "+1 212 555 0003", "1FTFW1ET5DF000003", "Ford", "F-150", 2020, "KJ-2020" ]
].each do |number, name, email, phone, vin, make, model, year, plate|
  customer_id = SeedSupport.uuid(0x70, number)
  SeedSupport.upsert!(Customer, customer_id, name: name, email: email, phone: phone)
  SeedSupport.upsert!(
    Vehicle,
    SeedSupport.uuid(0x71, number),
    customer_id: customer_id, vin: vin, make: make, model: model, year: year, license_plate: plate
  )
end
