# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::DunningCampaignFinishedSerializer do
  subject(:serializer) { described_class.new(customer, params) }

  let(:customer) { create(:customer) }
  let(:params) do
    {
      root_name: "dunning_campaign",
      dunning_campaign_code: "campaign_code"
    }
  end

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["dunning_campaign"]["customer_external_id"]).to eq(customer.external_id)
    expect(result["dunning_campaign"]["dunning_campaign_code"]).to eq("campaign_code")
    expect(result["dunning_campaign"]["overdue_balance_cents"]).to eq(customer.overdue_balance_cents)
    expect(result["dunning_campaign"]["overdue_balance_currency"]).to eq(customer.currency)
  end
end
