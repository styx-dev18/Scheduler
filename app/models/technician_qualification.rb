class TechnicianQualification < ApplicationRecord
  belongs_to :technician
  belongs_to :qualification

  validates :qualification_id, uniqueness: { scope: :technician_id }
end
