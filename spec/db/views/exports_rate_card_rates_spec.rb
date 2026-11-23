# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_rate_card_rates view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }

  let(:rate_card_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_model: "package",
      rate_properties: {"amount" => "100", "free_units" => 0, "package_size" => 10},
      min_amount_cents: 500,
      billing_interval_count: 3,
      billing_interval_unit: "week"
    )
  end

  let(:pricing_unit_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card: create(:rate_card, organization:, applied_pricing_unit_code: "credits"),
      applied_pricing_unit_conversion_rate: "0.25"
    )
  end

  let(:deleted_rate_card_rate) { create(:rate_card_rate, organization:, deleted_at: Time.current) }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_rate_card_rates ORDER BY created_at, lago_id")
  end

  def row_for(record)
    result.to_a.find { |row| row["lago_id"] == record.id }
  end

  before do
    rate_card_rate
    pricing_unit_rate
    deleted_rate_card_rate
  end

  it "exports the columns in order" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_rate_card_id
        code
        effective_from
        rate_model
        rate_properties
        min_amount_cents
        billing_interval_count
        billing_interval_unit
        applied_pricing_unit_conversion_rate
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the rate with its enums as strings and its properties as JSON" do
    row = row_for(rate_card_rate)

    expect(row).to include(
      "organization_id" => organization.id,
      "lago_rate_card_id" => rate_card_rate.rate_card_id,
      "code" => rate_card_rate.code,
      "rate_model" => "package",
      "min_amount_cents" => 500,
      "billing_interval_count" => 3,
      "billing_interval_unit" => "week",
      "applied_pricing_unit_conversion_rate" => nil,
      "deleted_at" => nil
    )
    expect(row["effective_from"]).to eq(rate_card_rate.effective_from)
    expect(JSON.parse(row["rate_properties"])).to eq("amount" => "100", "free_units" => 0, "package_size" => 10)
  end

  it "exports the pricing unit conversion rate" do
    expect(row_for(pricing_unit_rate)["applied_pricing_unit_conversion_rate"]).to eq(BigDecimal("0.25"))
  end

  it "exports soft-deleted rates with their deleted_at" do
    expect(row_for(deleted_rate_card_rate)["deleted_at"]).to be_present
  end
end
