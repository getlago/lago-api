# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::PremiumIntegrationTypeEnum do
  let(:premium_integration_types) do
    %w[
      beta_payment_authorization
      api_permissions
      auto_dunning
      hubspot
      netsuite
      okta
      progressive_billing
      lifetime_usage
      revenue_analytics
      revenue_share
      salesforce
      xero
      zero_amount_fees
      remove_branding_watermark
      manual_payments
      from_email
      issue_receipts
      preview
      multi_entities_pro
      multi_entities_enterprise
      analytics_dashboards
    ]
  end

  it "enumerizes the correct values" do
    expect(described_class.values.keys).to match_array(premium_integration_types)
  end
end
