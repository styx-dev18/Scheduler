require "rails_helper"

RSpec.describe DealershipHoliday do
  subject { create(:dealership_holiday) }

  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to validate_presence_of(:holiday_on) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:holiday_on).scoped_to(:dealership_id) }
end
