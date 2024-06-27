require 'rails_helper'

RSpec.describe DataExport, type: :model do
  it { is_expected.to belong_to(:user) }

  it { is_expected.to validate_presence_of(:format) }
  it { is_expected.to validate_presence_of(:resource_type) }
  it { is_expected.to validate_presence_of(:resource_query) }
  it { is_expected.to validate_presence_of(:status) }
end
