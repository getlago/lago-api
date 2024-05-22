require 'rails_helper'

RSpec.describe IntegrationResource, type: :model do
  subject(:integration_resource) { create(:integration_resource) }

  it { is_expected.to belong_to(:syncable) }
  it { is_expected.to belong_to(:integration) }

  it { is_expected.to define_enum_for(:resource_type).with_values(%i[invoice sales_order payment credit_note]) }
end
