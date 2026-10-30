class ServiceTypeSerializer
  include Alba::Resource

  attributes :id, :name, :description, :duration_minutes
end
