# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_daily_usages view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:subscription_daily_usage) { create(:daily_usage, organization:, customer:) }
  let(:contract_daily_usage) { create(:daily_usage, :contract, organization:, customer:) }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_daily_usages ORDER BY created_at, lago_id")
  end

  def row_for(daily_usage)
    result.to_a.find { |row| row["lago_id"] == daily_usage.id }
  end

  before do
    subscription_daily_usage
    contract_daily_usage
  end

  it "keeps the existing columns first and appends the contract columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        from_datetime
        to_datetime
        refreshed_at
        usage_date
        daily_usage
        daily_usage_diff
        created_at
        updated_at
        lago_customer_id
        lago_subscription_id
        external_subscription_id
        lago_contract_id
        external_contract_id
        lago_contract_rate_card_id
      ]
    )
  end

  it "exports subscription daily usages with null contract columns" do
    expect(row_for(subscription_daily_usage)).to include(
      "organization_id" => organization.id,
      "lago_customer_id" => customer.id,
      "lago_subscription_id" => subscription_daily_usage.subscription_id,
      "external_subscription_id" => subscription_daily_usage.external_subscription_id,
      "lago_contract_id" => nil,
      "external_contract_id" => nil,
      "lago_contract_rate_card_id" => nil
    )
  end

  it "exports contract daily usages with null subscription columns" do
    expect(row_for(contract_daily_usage)).to include(
      "organization_id" => organization.id,
      "lago_customer_id" => customer.id,
      "lago_subscription_id" => nil,
      "external_subscription_id" => nil,
      "lago_contract_id" => contract_daily_usage.contract_id,
      "external_contract_id" => contract_daily_usage.external_contract_id,
      "lago_contract_rate_card_id" => contract_daily_usage.contract_rate_card_id
    )
  end
end
