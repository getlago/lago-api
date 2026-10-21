# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardSerializer do
  subject(:payload) { described_class.new(rate_card, options).serialize }

  # Pinned so that timestamps and rate statuses have literal values.
  around { |example| travel_to(Time.zone.parse("2026-10-15T10:00:00Z")) { example.run } }

  let(:organization) { create(:organization) }
  let(:created_at) { Time.zone.parse("2026-10-01T09:00:00Z") }
  let(:rate_card) { create(:rate_card, organization:, created_at:) }
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: rate_card.id,
      product_code: rate_card.product.code,
      product_filter_code: nil,
      name: rate_card.name,
      code: rate_card.code,
      description: "test description",
      currency: "EUR",
      billing_timing: "arrears",
      proration: false,
      display_on_invoice: true,
      regroup_paid_fees: nil,
      applied_pricing_unit_code: nil,
      rates_count: 0,
      created_at: "2026-10-01T09:00:00Z",
      updated_at: "2026-10-15T10:00:00Z",
      deleted_at: nil
    }
  end

  let(:terminated_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      code: "launch",
      effective_from: Time.zone.parse("2026-08-01"),
      rate_properties: {"amount" => "8"}
    )
  end
  let(:active_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      code: "current",
      effective_from: Time.zone.parse("2026-09-01"),
      rate_properties: {"amount" => "12"}
    )
  end
  let(:pending_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      code: "next",
      effective_from: Time.zone.parse("2026-11-01"),
      rate_properties: {"amount" => "15"}
    )
  end
  # Latest effective rate if it were kept: it must not become the active rate.
  let(:deleted_rate) do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      code: "withdrawn",
      effective_from: Time.zone.parse("2026-10-01"),
      rate_properties: {"amount" => "20"},
      deleted_at: Time.current
    )
  end

  let(:terminated_rate_payload) do
    {
      lago_id: terminated_rate.id,
      code: "launch",
      effective_from: "2026-08-01T00:00:00Z",
      status: "terminated",
      rate_model: "standard",
      rate_properties: {"amount" => "8"},
      min_amount_cents: 0,
      billing_interval_count: 1,
      billing_interval_unit: "month",
      applied_pricing_unit_conversion_rate: nil,
      created_at: "2026-10-15T10:00:00Z",
      updated_at: "2026-10-15T10:00:00Z",
      deleted_at: nil
    }
  end
  let(:active_rate_payload) do
    {
      lago_id: active_rate.id,
      code: "current",
      effective_from: "2026-09-01T00:00:00Z",
      status: "active",
      rate_model: "standard",
      rate_properties: {"amount" => "12"},
      min_amount_cents: 0,
      billing_interval_count: 1,
      billing_interval_unit: "month",
      applied_pricing_unit_conversion_rate: nil,
      created_at: "2026-10-15T10:00:00Z",
      updated_at: "2026-10-15T10:00:00Z",
      deleted_at: nil
    }
  end
  let(:pending_rate_payload) do
    {
      lago_id: pending_rate.id,
      code: "next",
      effective_from: "2026-11-01T00:00:00Z",
      status: "pending",
      rate_model: "standard",
      rate_properties: {"amount" => "15"},
      min_amount_cents: 0,
      billing_interval_count: 1,
      billing_interval_unit: "month",
      applied_pricing_unit_conversion_rate: nil,
      created_at: "2026-10-15T10:00:00Z",
      updated_at: "2026-10-15T10:00:00Z",
      deleted_at: nil
    }
  end

  it "serializes the rate card, without includes" do
    expect(payload).to eq(flat_payload)
  end

  context "when the rate card is deleted" do
    let(:rate_card) { create(:rate_card, organization:, created_at:, deleted_at: Time.zone.parse("2026-10-12T08:00:00Z")) }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-10-12T08:00:00Z"))
    end
  end

  context "when the rate card prices a product filter" do
    let(:rate_card) { create(:rate_card, :with_filter, organization:, created_at:) }

    it "renders the filter code" do
      expect(payload).to eq(flat_payload.merge(product_filter_code: rate_card.product_filter.code))
    end
  end

  context "with the active_rate include, when no rate is effective yet" do
    let(:options) { {includes: %i[active_rate]} }

    before { pending_rate }

    it "renders a null active rate" do
      expect(payload).to eq(flat_payload.merge(rates_count: 1, active_rate: nil))
    end
  end

  context "with the taxes include" do
    let(:options) { {includes: %i[taxes]} }
    let(:tax) { create(:tax, organization:, code: "vat_fr", name: "VAT", rate: 20.0, description: "French Standard VAT") }

    before { create(:rate_card_applied_tax, organization:, rate_card:, tax:) }

    it "embeds the applied taxes" do
      expect(payload).to eq(
        flat_payload.merge(
          taxes: [
            {
              lago_id: tax.id,
              name: "VAT",
              code: "vat_fr",
              rate: 20.0,
              description: "French Standard VAT",
              applied_to_organization: false,
              add_ons_count: 0,
              customers_count: 0,
              plans_count: 0,
              charges_count: 0,
              commitments_count: 0,
              created_at: "2026-10-15T10:00:00Z"
            }
          ]
        )
      )
    end
  end

  context "with a timeline of rates" do
    before do
      terminated_rate
      active_rate
      deleted_rate
      pending_rate
    end

    it "counts the kept rates only" do
      expect(payload).to eq(flat_payload.merge(rates_count: 3))
    end

    context "with the active_rate include" do
      let(:options) { {includes: %i[active_rate]} }

      it "embeds the latest effective rate" do
        expect(payload).to eq(flat_payload.merge(rates_count: 3, active_rate: active_rate_payload))
      end
    end

    context "with the rates include" do
      let(:options) { {includes: %i[rates]} }

      # The rates relation has no order, so the list is compared without one.
      it "embeds every kept rate" do
        expect(payload).to match(
          flat_payload.merge(
            rates_count: 3,
            rates: contain_exactly(terminated_rate_payload, active_rate_payload, pending_rate_payload)
          )
        )
      end
    end
  end
end
