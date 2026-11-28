# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RefreshDraftService do
  subject(:result) { described_class.call(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) do
    create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1))
  end
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, billing_timing:, organization:, product:, currency: "USD") }
  let(:billing_timing) { "advance" }
  let(:billing_scope) { "cycle" }
  let(:pricing_unit_conversion_rate) { nil }
  let(:operation_cycles) { [1, 2, 3] }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:, contract:, rate_card:, billing_scope:,
      billing_anchor_date: Date.new(2026, 1, 1),
      effective_date: Date.new(2026, 1, 1)
    )
  end
  let(:invoice) do
    create(
      :invoice, :draft, organization:, customer:, billing_entity: customer.billing_entity,
      invoice_type: :contract, currency: "USD", ready_to_be_refreshed: true,
      total_amount_cents: 444, fees_amount_cents: 444
    )
  end
  let(:rate_card_rate) do
    create(
      :rate_card_rate,
      organization:, rate_card:,
      effective_from: Time.utc(2025, 1, 1),
      billing_interval_count: 1,
      billing_interval_unit: "month",
      applied_pricing_unit_conversion_rate: pricing_unit_conversion_rate,
      rate_properties: {"amount" => "15.00"}
    )
  end
  let(:initial_fee) do
    create(
      :fee, invoice:, organization:, contract:, contract_rate_card:,
      amount_cents: 444,
      properties: {"timestamp" => "2026-03-01T00:00:00Z"}
    )
  end

  before do
    travel_to(Time.utc(2026, 6, 1))
    rate_card_rate
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: 2)
    initial_fee
    operation_cycles.each do |month|
      cycle_start = Time.utc(2026, month, 1)
      billing_at = (billing_timing == "advance") ? cycle_start : cycle_start + 1.month
      create(:billing_operation, organization:, customer:, contract_rate_card:, invoice:,
        action_type: (billing_timing == "advance") ? "renew_fixed_advance" : "close_fixed_arrears",
        reason: :periodic_continuation, billing_at:, target_cycle_started_at: cycle_start, processed_at: billing_at)
    end
  end

  def fee_coverage
    invoice.fees.map do |fee|
      [fee.properties["from_datetime"], fee.properties["to_datetime"], fee.amount_cents]
    end.sort_by(&:first)
  end

  context "when no operations are linked" do
    let(:operation_cycles) { [] }

    before do
      invoice.update!(taxes_amount_cents: 44, sub_total_excluding_taxes_amount_cents: 400,
        sub_total_including_taxes_amount_cents: 444)
    end

    it "preserves the draft when its fee references a card" do
      expect(result).to be_failure
      expect(result.error.code).to eq("missing_billing_operations")
      expect(invoice.reload).to have_attributes(
        status: "draft", ready_to_be_refreshed: true, total_amount_cents: 444, fees_amount_cents: 444,
        taxes_amount_cents: 44, sub_total_excluding_taxes_amount_cents: 400,
        sub_total_including_taxes_amount_cents: 444
      )
      expect(invoice.fees.pluck(:id, :amount_cents)).to eq([[initial_fee.id, 444]])
    end
  end

  it "rebuilds the advance coverage owned by the linked operations" do
    expect(result).to be_success

    expect(invoice.reload.fees.count).to eq(3)
    expect(fee_coverage).to eq([
      [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6), 3_000],
      [Time.utc(2026, 2, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 3, 1)).iso8601(6), 3_000],
      [Time.utc(2026, 3, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 4, 1)).iso8601(6), 3_000]
    ])
    expect(invoice.total_amount_cents).to eq(3 * 2 * 1_500) # Three cycles, two units at $15 each.
    expect(invoice.fees.pluck(Arel.sql("properties ->> 'timestamp'")).map { Time.iso8601(it) }.sort)
      .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)])
    first_coverage = fee_coverage
    first_total = invoice.total_amount_cents
    second_result = described_class.call(invoice:)

    expect(second_result).to be_success
    expect(fee_coverage).to eq(first_coverage)
    expect(invoice.reload.total_amount_cents).to eq(first_total)
  end

  context "when the invoice has linked billing operations" do
    let(:operation_cycles) { [] }
    let(:operation_attributes) do
      {
        action_type: "renew_fixed_advance",
        reason: :periodic_continuation,
        billing_at: Time.utc(2026, 3, 1),
        target_cycle_started_at: Time.utc(2026, 3, 1)
      }
    end

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, invoice:,
        processed_at: operation_attributes[:billing_at], **operation_attributes)
    end

    it "rebuilds only the slices covered by those operations" do
      expect(result).to be_success

      expect(invoice.reload.fees.count).to eq(1)
      expect(fee_coverage).to eq([
        [Time.utc(2026, 3, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 4, 1)).iso8601(6), 3_000]
      ])
      expect(invoice.total_amount_cents).to eq(3_000)

      first_coverage = fee_coverage
      expect(described_class.call(invoice:)).to be_success
      expect(fee_coverage).to eq(first_coverage)
    end

    context "when an arrears cycle has multiple due slices" do
      let(:billing_timing) { "arrears" }
      let(:operation_attributes) do
        {
          action_type: "close_fixed_arrears",
          reason: :periodic_continuation,
          billing_at: Time.utc(2026, 2, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1)
        }
      end

      before do
        create(
          :rate_card_rate, organization:, rate_card:,
          effective_from: Time.utc(2026, 1, 15),
          billing_interval_count: 1, billing_interval_unit: "month",
          rate_properties: {"amount" => "20.00"}
        )
      end

      it "rebuilds every slice of the cycle that no earlier operation owns" do
        expect(result).to be_success

        expect(fee_coverage).to eq([
          [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 1, 15)).iso8601(6), 3_000],
          [Time.utc(2026, 1, 15).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6), 4_000]
        ])
        expect(invoice.fees.pluck(Arel.sql("properties ->> 'timestamp'")).map { Time.iso8601(it) }.uniq)
          .to eq([Time.utc(2026, 2, 1)])
      end

      context "when an earlier operation of the cycle owns the first slice" do
        let(:billing_scope) { "segment" }

        before do
          create(:billing_operation, organization:, customer:, contract_rate_card:,
            action_type: "close_fixed_arrears", reason: :periodic_continuation,
            billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1),
            processed_at: Time.utc(2026, 1, 15))
        end

        it "rebuilds only the linked later slice and preserves its billing timestamp" do
          expect(result).to be_success

          expect(fee_coverage).to eq([
            [Time.utc(2026, 1, 15).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6), 4_000]
          ])
          expect(invoice.fees.pluck(Arel.sql("properties ->> 'timestamp'")).map { Time.iso8601(it) }.uniq)
            .to eq([Time.utc(2026, 2, 1)])
        end
      end
    end

    context "when the invoice consolidates operations for multiple cards" do
      let(:second_product) { create(:product, :fixed, organization:) }
      let(:second_rate_card) { create(:rate_card, :advance, organization:, product: second_product, currency: "USD") }
      let(:second_contract_rate_card) do
        create(
          :contract_rate_card, organization:, contract:, rate_card: second_rate_card,
          billing_anchor_date: Date.new(2026, 1, 1), effective_date: Date.new(2026, 1, 1), units: 1
        )
      end

      before do
        create(
          :rate_card_rate, organization:, rate_card: second_rate_card,
          effective_from: Time.utc(2025, 1, 1), billing_interval_count: 1,
          billing_interval_unit: "month", rate_properties: {"amount" => "10.00"},
          applied_pricing_unit_conversion_rate: pricing_unit_conversion_rate
        )
        create(
          :billing_operation, organization:, customer:, contract_rate_card: second_contract_rate_card, invoice:,
          action_type: "renew_fixed_advance", reason: :periodic_continuation,
          billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 3, 1),
          processed_at: Time.utc(2026, 3, 1)
        )
      end

      it "rebuilds only the current-cycle slice for each linked card" do
        expect(result).to be_success

        expect(fee_coverage).to match_array([
          [Time.utc(2026, 3, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 4, 1)).iso8601(6), 3_000],
          [Time.utc(2026, 3, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 4, 1)).iso8601(6), 1_000]
        ])
        expect(invoice.fees.count).to eq(2)
      end

      context "with custom pricing units" do
        let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }
        let(:pricing_unit_conversion_rate) { 1 }
        let(:rate_card) do
          create(:rate_card, :advance, organization:, product:, currency: "USD", applied_pricing_unit_code: pricing_unit.code)
        end
        let(:second_rate_card) do
          create(:rate_card, :advance, organization:, product: second_product, currency: "USD", applied_pricing_unit_code: pricing_unit.code)
        end

        it "loads pricing units once and reuses loaded filters when refreshing all slices" do
          lookup_queries = []
          allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_wrap_original do |original, **attributes|
            lookup_queries.concat(capture_sql do
              attributes.fetch(:billing_segments).each do |segment|
                target = Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment: segment)
                target.filters
                target.filters
              end
            end)
            original.call(**attributes)
          end

          queries = capture_sql { result }

          expect(result).to be_success
          expect(invoice.fees.map { it.pricing_unit_usage.pricing_unit_id }).to eq([pricing_unit.id, pricing_unit.id])
          expect(queries.grep(/FROM "pricing_units"/).size).to eq(1)
          expect(lookup_queries).to be_empty
        end
      end
    end
  end

  context "when the resolved segments are accessed again" do
    let(:refresh_service) { described_class.new(invoice:) }

    it "reuses the same segments without querying their source again" do
      segments = refresh_service.send(:billing_segments)

      statements = capture_sql do
        expect(refresh_service.send(:billing_segments)).to equal(segments)
      end

      expect(statements).to be_empty
    end
  end

  context "when the rate card bills in arrears" do
    let(:billing_timing) { "arrears" }
    let(:operation_cycles) { [1, 2] }

    it "does not include the currently unclosed March cycle" do
      expect(result).to be_success

      expect(invoice.reload.fees.count).to eq(2)
      expect(fee_coverage).to eq([
        [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6), 3_000],
        [Time.utc(2026, 2, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 3, 1)).iso8601(6), 3_000]
      ])
    end
  end

  context "when multiple fees reference the same card" do
    let(:second_initial_fee) do
      create(
        :fee, invoice:, organization:, contract:, contract_rate_card:,
        amount_cents: 444,
        properties: {"timestamp" => "2026-03-01T00:00:00Z"}
      )
    end

    before { second_initial_fee }

    it "rebuilds each due slice only once" do
      expect(result).to be_success

      expect(invoice.reload.fees.count).to eq(3)
      expect(invoice.total_amount_cents).to eq(9_000)
    end
  end

  context "when other cards are not referenced by the invoice" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
    let(:other_rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
    let(:other_contract_rate_card) do
      create(
        :contract_rate_card, organization:, contract: other_contract, rate_card: other_rate_card,
        billing_anchor_date: Date.new(2026, 1, 1), effective_date: Date.new(2026, 1, 1)
      )
    end
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization, timezone: "UTC") }
    let(:foreign_contract) do
      create(:contract, organization: other_organization, customer: other_customer, started_at: Time.utc(2026, 1, 1))
    end
    let(:foreign_product) { create(:product, :fixed, organization: other_organization) }
    let(:foreign_rate_card) { create(:rate_card, organization: other_organization, product: foreign_product, currency: "USD") }
    let(:foreign_contract_rate_card) do
      create(
        :contract_rate_card, organization: other_organization, contract: foreign_contract,
        rate_card: foreign_rate_card, billing_anchor_date: Date.new(2026, 1, 1),
        effective_date: Date.new(2026, 1, 1)
      )
    end

    before do
      other_contract_rate_card
      foreign_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.utc(2025, 1, 1),
        billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {"amount" => "10.00"})
      create(:rate_card_rate, organization: other_organization, rate_card: foreign_rate_card,
        effective_from: Time.utc(2025, 1, 1), billing_interval_count: 1, billing_interval_unit: "month",
        rate_properties: {"amount" => "20.00"})
      create(:contract_rate_card_term, organization:, contract_rate_card: other_contract_rate_card, units: 1)
      create(:contract_rate_card_term, organization: other_organization, contract_rate_card: foreign_contract_rate_card, units: 1)
    end

    it "only rebuilds cards referenced by invoice operations and scoped to its organization" do
      expect(result).to be_success

      expect(invoice.reload.fees.count).to eq(3)
      expect(invoice.fees.pluck(:contract_rate_card_id).uniq).to eq([contract_rate_card.id])
    end
  end

  context "when the referenced card has no rates" do
    let(:rate_card_rate) { nil }

    it "rolls back the refresh and preserves the existing fees, totals, and ready flag" do
      expect(result).not_to be_success

      expect(invoice.reload).to have_attributes(
        ready_to_be_refreshed: true,
        total_amount_cents: 444,
        fees_amount_cents: 444
      )
      expect(invoice.fees.pluck(:id)).to eq([initial_fee.id])
      expect(invoice.billing_operations.count).to eq(3)
    end
  end
end
