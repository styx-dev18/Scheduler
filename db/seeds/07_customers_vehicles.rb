[
  [ 1, "Nguyen Thi Lan", "lan.nguyen@example.com", "+84 24 3946 0001", "RLLVF8000P0000001", "VinFast", "VF 8", 2023, "30K-123.45" ],
  [ 2, "Tran Minh Quan", "quan.tran@example.com", "+84 24 3946 0002", "RL4BT9F30M0000002", "Toyota", "Vios", 2021, "29A-456.78" ],
  [ 3, "Le Hoang Anh", "anh.le@example.com", "+84 28 3946 0003", "MNCLS4D20L0000003", "Ford", "Ranger", 2020, "51G-789.01" ]
].each do |number, name, email, phone, vin, make, model, year, plate|
  customer_id = SeedSupport.uuid(0x70, number)
  SeedSupport.upsert!(Customer, customer_id, name: name, email: email, phone: phone)
  SeedSupport.upsert!(
    Vehicle,
    SeedSupport.uuid(0x71, number),
    customer_id: customer_id, vin: vin, make: make, model: model, year: year, license_plate: plate
  )
end
