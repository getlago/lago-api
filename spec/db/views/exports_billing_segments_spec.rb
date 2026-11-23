# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_billing_segments view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
  let(:rate_override) { create(:rate_override, organization:) }
  let(:pricing_unit) { create(:pricing_unit, organization:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:cycle_started_at) { Time.zone.parse("2026-01-01 00:00:00") }
  let(:invoiced_segment_id) { SecureRandom.uuid }
  let(:overridden_segment_id) { SecureRandom.uuid }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_billing_segments ORDER BY started_at")
  end

  def row_for(id)
    result.to_a.find { |row| row["lago_id"] == id }
  end

  def segment_attributes(id:, started_at:, ended_at:, **attributes)
    {
      id:,
      organization_id: organization.id,
      customer_id: customer.id,
      contract_id: contract.id,
      contract_rate_card_id: contract_rate_card.id,
      invoice_id: nil,
      rate_card_rate_id: nil,
      rate_override_id: nil,
      pricing_unit_id: nil,
      rate_properties: {},
      proration_ratio: BigDecimal("1"),
      status: "pending",
      currency: "EUR",
      billing_at: started_at,
      started_at:,
      ended_at:,
      cycle_started_at:,
      created_at: Time.current,
      updated_at: Time.current
    }.merge(attributes)
  end

  before do
    # The model is read-only, so rows are seeded without its write API.
    LegacyBillingSegment.insert_all!([ # rubocop:disable Rails/SkipsModelValidations
      segment_attributes(
        id: invoiced_segment_id,
        started_at: cycle_started_at,
        ended_at: cycle_started_at + 14.days,
        invoice_id: invoice.id,
        rate_card_rate_id: rate_card_rate.id,
        rate_properties: {"amount" => "10"},
        proration_ratio: BigDecimal("0.5"),
        status: "done"
      ),
      segment_attributes(
        id: overridden_segment_id,
        started_at: cycle_started_at + 15.days,
        ended_at: cycle_started_at + 1.month - 1.second,
        rate_override_id: rate_override.id,
        pricing_unit_id: pricing_unit.id
      )
    ])
  end

  it "exports the columns in order" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_contract_id
        lago_customer_id
        lago_contract_rate_card_id
        lago_invoice_id
        lago_rate_card_rate_id
        lago_rate_override_id
        lago_pricing_unit_id
        rate_properties
        currency
        billing_at
        started_at
        ended_at
        cycle_started_at
        proration_ratio
        status
        created_at
        updated_at
      ]
    )
  end

  it "exports an invoiced segment with its status as a string and its properties as JSON" do
    row = row_for(invoiced_segment_id)

    expect(row).to include(
      "organization_id" => organization.id,
      "lago_contract_id" => contract.id,
      "lago_customer_id" => customer.id,
      "lago_contract_rate_card_id" => contract_rate_card.id,
      "lago_invoice_id" => invoice.id,
      "lago_rate_card_rate_id" => rate_card_rate.id,
      "lago_rate_override_id" => nil,
      "lago_pricing_unit_id" => nil,
      "currency" => "EUR",
      "billing_at" => cycle_started_at,
      "started_at" => cycle_started_at,
      "ended_at" => cycle_started_at + 14.days,
      "cycle_started_at" => cycle_started_at,
      "proration_ratio" => BigDecimal("0.5"),
      "status" => "done"
    )
    expect(JSON.parse(row["rate_properties"])).to eq("amount" => "10")
  end

  it "exports a pending segment priced by an override in a pricing unit" do
    expect(row_for(overridden_segment_id)).to include(
      "lago_invoice_id" => nil,
      "lago_rate_card_rate_id" => nil,
      "lago_rate_override_id" => rate_override.id,
      "lago_pricing_unit_id" => pricing_unit.id,
      "proration_ratio" => BigDecimal("1"),
      "status" => "pending"
    )
  end
end
