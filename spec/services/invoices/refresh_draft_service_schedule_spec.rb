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
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:, contract:, rate_card:,
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
  end

  def fee_coverage
    invoice.fees.map do |fee|
      [fee.properties["from_datetime"], fee.properties["to_datetime"], fee.amount_cents]
    end.sort_by(&:first)
  end

  it "rebuilds all advance slices due at the stored timestamp, with the schedule cutoff retained" do
    statements = capture_sql { result }

    expect(result).to be_success

    expect(invoice.reload.fees.count).to eq(3)
    expect(fee_coverage).to eq([
      [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6), 3_000],
      [Time.utc(2026, 2, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 3, 1)).iso8601(6), 3_000],
      [Time.utc(2026, 3, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 4, 1)).iso8601(6), 3_000]
    ])
    expect(invoice.total_amount_cents).to eq(3 * 2 * 1_500) # Three cycles, two units at $15 each.
    expect(invoice.fees.pluck(Arel.sql("properties ->> 'timestamp'")).map { Time.iso8601(it) }.uniq)
      .to eq([Time.utc(2026, 3, 1)])
    expect(statements.grep(/billing_operations/i)).to be_empty

    first_coverage = fee_coverage
    first_total = invoice.total_amount_cents
    second_result = described_class.call(invoice:)

    expect(second_result).to be_success
    expect(fee_coverage).to eq(first_coverage)
    expect(invoice.reload.total_amount_cents).to eq(first_total)
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

    it "only rebuilds cards referenced by invoice fees and scoped to its organization" do
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
      expect(BillingOperation.count).to eq(0)
    end
  end
end
