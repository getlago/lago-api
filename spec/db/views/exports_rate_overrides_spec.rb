# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_rate_overrides view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:created_at) { Time.zone.parse("2026-01-01 10:00:00") }
  let(:updated_at) { Time.zone.parse("2026-01-02 10:00:00") }

  let(:rate_override) do
    create(
      :rate_override,
      organization:,
      rate_model: "percentage",
      rate_properties: {"rate" => "2.5"},
      min_amount_cents: 1000,
      billing_interval_count: 2,
      billing_interval_unit: "month",
      pricing_unit_conversion_rate: "1.5",
      created_at:,
      updated_at:
    )
  end

  let(:default_rate_override) { create(:rate_override, organization:) }
  let(:deleted_rate_override) { create(:rate_override, organization:, deleted_at: Time.current) }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_rate_overrides ORDER BY created_at, lago_id")
  end

  def row_for(record)
    result.to_a.find { |row| row["lago_id"] == record.id }
  end

  before do
    rate_override
    default_rate_override
    deleted_rate_override
  end

  it "exports the columns in order" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        rate_model
        rate_properties
        min_amount_cents
        billing_interval_count
        billing_interval_unit
        pricing_unit_conversion_rate
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the override with its enums as strings and its properties as JSON" do
    row = row_for(rate_override)

    expect(row).to include(
      "organization_id" => organization.id,
      "rate_model" => "percentage",
      "min_amount_cents" => 1000,
      "billing_interval_count" => 2,
      "billing_interval_unit" => "month",
      "pricing_unit_conversion_rate" => BigDecimal("1.5"),
      "created_at" => created_at,
      "updated_at" => updated_at,
      "deleted_at" => nil
    )
    expect(JSON.parse(row["rate_properties"])).to eq("rate" => "2.5")
  end

  it "exports null interval columns when the override keeps the rate's interval" do
    expect(row_for(default_rate_override)).to include(
      "billing_interval_count" => nil,
      "billing_interval_unit" => nil,
      "pricing_unit_conversion_rate" => nil
    )
  end

  it "exports soft-deleted overrides with their deleted_at" do
    expect(row_for(deleted_rate_override)["deleted_at"]).to be_present
  end
end
