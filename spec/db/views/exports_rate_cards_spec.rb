# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_rate_cards view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:created_at) { Time.zone.parse("2026-01-01 10:00:00") }
  let(:updated_at) { Time.zone.parse("2026-01-02 10:00:00") }

  let(:rate_card) do
    create(
      :rate_card,
      :with_filter,
      organization:,
      description: "Card description",
      currency: "USD",
      applied_pricing_unit_code: "credits",
      created_at:,
      updated_at:
    )
  end

  let(:regrouped_rate_card) do
    create(:rate_card, :advance, organization:, display_on_invoice: false, regroup_paid_fees: "invoice")
  end

  let(:deleted_rate_card) { create(:rate_card, organization:, deleted_at: Time.current) }

  let(:result) do
    ActiveRecord::Base.connection.select_all("SELECT * FROM exports_rate_cards ORDER BY created_at, lago_id")
  end

  def row_for(record)
    result.to_a.find { |row| row["lago_id"] == record.id }
  end

  before do
    rate_card
    regrouped_rate_card
    deleted_rate_card
  end

  it "exports the columns in order" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_product_id
        lago_product_filter_id
        code
        name
        description
        currency
        billing_timing
        proration
        display_on_invoice
        regroup_paid_fees
        applied_pricing_unit_code
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the rate card with its enums as strings" do
    expect(row_for(rate_card)).to include(
      "organization_id" => organization.id,
      "lago_product_id" => rate_card.product_id,
      "lago_product_filter_id" => rate_card.product_filter_id,
      "code" => rate_card.code,
      "name" => rate_card.name,
      "description" => "Card description",
      "currency" => "USD",
      "billing_timing" => "arrears",
      "proration" => false,
      "display_on_invoice" => true,
      "regroup_paid_fees" => nil,
      "applied_pricing_unit_code" => "credits",
      "created_at" => created_at,
      "updated_at" => updated_at,
      "deleted_at" => nil
    )
  end

  it "exports the regroup paid fees and advance billing timing" do
    expect(row_for(regrouped_rate_card)).to include(
      "lago_product_filter_id" => nil,
      "billing_timing" => "advance",
      "display_on_invoice" => false,
      "regroup_paid_fees" => "invoice"
    )
  end

  it "exports soft-deleted rate cards with their deleted_at" do
    expect(row_for(deleted_rate_card)["deleted_at"]).to be_present
  end
end
