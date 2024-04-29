# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::IntegrationCustomerSerializer do
  subject(:serializer) { described_class.new(integration_customer, root_name: 'integration_customer') }

  let(:integration_customer) { create(:netsuite_customer) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    expect(result['integration_customer']).to include(
      'lago_id' => integration_customer.id,
      'external_customer_id' => integration_customer.external_customer_id,
      'type' => 'netsuite',
      'sync_with_provider' => integration_customer.sync_with_provider,
      'subsidiary_id' => integration_customer.subsidiary_id,
    )
  end
end
