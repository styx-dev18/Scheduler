module SeedSupport
  module_function

  def uuid(namespace, number)
    format("%08x-0000-4000-8000-%012d", namespace, number)
  end

  def upsert!(model, id, attributes)
    record = model.find_or_initialize_by(id: id)
    record.update!(attributes)
    record
  end
end

Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |file| load file }
