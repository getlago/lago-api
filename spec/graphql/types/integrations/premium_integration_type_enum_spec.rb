# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::PremiumIntegrationTypeEnum do
  let(:premium_integration_types) do
    %w[
      api_permissions
      auto_dunning
      hubspot
      manual_payments
      netsuite
      okta
      progressive_billing
      revenue_analytics
      revenue_share
      salesforce
      xero
    ]
  end

  it 'enumerizes the correct values' do
    expect(described_class.values.keys).to match_array(premium_integration_types)
  end
end
