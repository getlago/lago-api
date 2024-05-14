require 'rails_helper'

RSpec.describe IntegrationResource, type: :model do
  subject(:integration_resource) { create(:integration_resource) }

  it { is_expected.to belong_to(:syncable) }
end
