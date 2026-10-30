[
  [ 1, "GENERAL_SERVICE", "General Service" ],
  [ 2, "LIFT_CERTIFIED", "Lift Certified" ],
  [ 3, "ALIGNMENT_CERTIFIED", "Alignment Certified" ]
].each do |number, code, name|
  SeedSupport.upsert!(Qualification, SeedSupport.uuid(0x10, number), code: code, name: name)
end
