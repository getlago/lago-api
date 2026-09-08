# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ScheduleService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, proration: true) }
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1),
      rate_properties: {"amount" => "100"})
  end
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.utc(2026, 2, 1))
  end
  let(:timestamp) { Time.utc(2026, 2, 1) }

  around { |example| travel_to(timestamp) { example.run } }

  before do
    rate
    card
  end

  it "persists the due segment and advances the billing clock" do
    expect { result }.to change(BillingSegment, :count).by(1)

    expect(result).to be_success
    segment = result.billing_segments.sole
    expect(segment).to have_attributes(
      organization_id: organization.id, contract_id: contract.id, customer_id: customer.id,
      contract_rate_card_id: card.id, rate_card_rate_id: rate.id,
      rate_override_id: nil, currency: rate_card.currency, status: "pending",
      started_at: Time.utc(2026, 1, 1), cycle_started_at: Time.utc(2026, 1, 1),
      ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)),
      billing_at: timestamp, rate_properties: {"amount" => "100"}, proration_ratio: 1
    )
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  it "does not duplicate segments on repeated runs" do
    result

    retry_result = described_class.call(customer:, timestamp:)

    expect(retry_result).to be_success
    expect(retry_result.billing_segments).to eq([])
    expect(BillingSegment.count).to eq(1)
  end

  it "resumes at the last cycle and adds only the newly due segment" do
    result

    next_result = described_class.call(customer:, timestamp: Time.utc(2026, 3, 1))

    expect(next_result.billing_segments.map(&:started_at)).to eq([Time.utc(2026, 2, 1)])
    expect(BillingSegment.count).to eq(2)
  end

  it "preserves an existing snapshot when replaying a stale clock" do
    result
    existing = BillingSegment.sole
    existing.update!(rate_properties: {"amount" => "80"}, status: :done)
    card.update!(next_billing_at: timestamp)

    replay = described_class.call(customer:, timestamp:)

    expect(replay).to be_success
    expect(replay.billing_segments).to eq([])
    expect(existing.reload).to have_attributes(rate_properties: {"amount" => "80"}, status: "done")
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  it "scopes scheduling to this customer's organization and contracts" do
    other = create(:contract_rate_card, next_billing_at: timestamp)

    result

    expect(result.billing_segments.map(&:contract_rate_card_id)).to eq([card.id])
    expect(other.reload.next_billing_at).to eq(timestamp)
  end

  context "when the seeded billing date has not arrived" do
    let(:timestamp) { Time.utc(2026, 1, 31, 23, 59, 59) }

    it "does not bill a period early" do
      expect { result }.not_to change(BillingSegment, :count)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end

  context "when processing is delayed" do
    let(:timestamp) { Time.utc(2026, 4, 10) }

    it "catches up all due periods and preserves their original billing dates" do
      expect(result.billing_segments.map(&:billing_at))
        .to eq([Time.utc(2026, 2, 1), Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)])
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 5, 1))
    end

    it "respects a backdated contract's seeded clock without billing its earlier history" do
      card.update!(next_billing_at: Time.utc(2026, 4, 1))

      expect(result.billing_segments.map(&:started_at)).to eq([Time.utc(2026, 3, 1)])
    end
  end

  context "with a rate change inside the cycle" do
    let(:timestamp) { Time.utc(2026, 1, 16) }
    let(:new_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp,
        rate_properties: {"amount" => "200"})
    end

    before do
      new_rate
      card.update!(next_billing_at: timestamp)
    end

    it "produces the first slice when due and the remainder on the next run" do
      first = result.billing_segments.sole
      expect(first).to have_attributes(rate_card_rate_id: rate.id, billing_at: timestamp,
        ended_at: BillingSegment.inclusive_end(timestamp), proration_ratio: BigDecimal("0.4838709677"))

      next_result = described_class.call(customer:, timestamp: Time.utc(2026, 2, 1))
      second = next_result.billing_segments.sole
      expect(second).to have_attributes(started_at: timestamp, cycle_started_at: first.cycle_started_at,
        rate_card_rate_id: new_rate.id, rate_properties: {"amount" => "200"})
      expect(BillingSegment.count).to eq(2)
    end

    it "keeps all slices when the initial clock was seeded before the rate change" do
      card.update!(next_billing_at: Time.utc(2026, 2, 1))

      produced = described_class.call(customer:, timestamp: Time.utc(2026, 2, 1)).billing_segments

      expect(produced.map(&:rate_card_rate_id)).to eq([rate.id, new_rate.id])
    end
  end

  context "with advance billing" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, proration: true) }
    let(:timestamp) { Time.utc(2026, 1, 1) }

    before { card.update!(next_billing_at: timestamp) }

    it "persists the whole priced segment at its opening boundary" do
      expect(result.billing_segments.sole).to have_attributes(
        billing_at: timestamp, started_at: timestamp,
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1))
      )
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end

  context "with a contract phase override" do
    let(:override) { create(:rate_override, organization:, rate_properties: {"amount" => "25"}) }

    before do
      create(:rate_phase, :contract_level, organization:, contract_rate_card: card, rate_override: override)
    end

    it "persists the resolved override and its properties" do
      expect(result.billing_segments.sole).to have_attributes(rate_card_rate_id: rate.id,
        rate_override_id: override.id, rate_properties: {"amount" => "25"})
    end
  end

  context "with phases inherited from the catalog plan" do
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:override) { create(:rate_override, organization:, rate_properties: {"amount" => "50"}) }

    before do
      contract.update!(catalog_plan:)
      plan_rate_card = create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
      create(:rate_phase, organization:, plan_rate_card:, rate_override: override)
    end

    it "persists the plan's resolved price" do
      expect(result.billing_segments.sole).to have_attributes(
        rate_override_id: override.id, rate_properties: {"amount" => "50"}
      )
    end
  end

  context "with customer-local boundaries across daylight saving time" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:timestamp) { Time.utc(2026, 4, 1, 4) }

    before do
      card.update!(effective_date: Date.new(2026, 3, 1), billing_anchor_date: Date.new(2026, 3, 1),
        next_billing_at: timestamp)
    end

    it "persists inclusive UTC boundaries without changing day-based proration" do
      expect(result.billing_segments.sole).to have_attributes(
        started_at: Time.utc(2026, 3, 1, 5), ended_at: BillingSegment.inclusive_end(timestamp),
        billing_at: timestamp, proration_ratio: 1
      )
    end
  end

  context "with a pricing unit" do
    let(:pricing_unit) { create(:pricing_unit, organization:) }
    let(:rate_card) { create(:rate_card, organization:, applied_pricing_unit_code: pricing_unit.code) }
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1),
        applied_pricing_unit_conversion_rate: 0.5)
    end

    it "stores the pricing unit alongside the currency" do
      expect(result.billing_segments.sole).to have_attributes(pricing_unit_id: pricing_unit.id,
        currency: rate_card.currency, pricing_unit_conversion_rate: 0.5)
    end
  end

  context "when the attachment ends" do
    before { card.update!(ended_date: Date.new(2026, 1, 20)) }

    it "produces the final due segment and clears the exhausted clock" do
      expect(result.billing_segments.sole).to have_attributes(
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 1, 21)),
        billing_at: Time.utc(2026, 1, 21)
      )
      expect(card.reload.next_billing_at).to be_nil
      expect(described_class.call(customer:, timestamp:).billing_segments).to eq([])
    end
  end

  context "when pricing starts in the future" do
    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 3, 1)) }

    it "moves the clock to the next priced segment even when nothing is produced" do
      expect(result).to be_success
      expect(result.billing_segments).to eq([])
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))
    end
  end

  context "when another card has an invalid schedule" do
    before do
      other_rate_card = create(:rate_card, organization:)
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
        next_billing_at: timestamp, id: "ffffffff-ffff-ffff-ffff-ffffffffffff")
    end

    it "rolls back every segment and clock for the customer" do
      expect { result }.not_to change(BillingSegment, :count)
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.billing_segments).to eq([])
      expect(card.reload.next_billing_at).to eq(timestamp)
    end
  end

  context "with an overlapping persisted segment" do
    before do
      create(:billing_segment, organization:, contract:, customer:, contract_rate_card: card,
        rate_card_rate: rate, cycle_started_at: Time.utc(2026, 1, 1), started_at: Time.utc(2026, 1, 15),
        ended_at: BillingSegment.inclusive_end(timestamp))
    end

    it "fails without advancing the clock or returning rolled-back rows" do
      expect { result }.not_to change(BillingSegment, :count)
      expect(result).to be_failure
      expect(result.error.messages).to eq(billing_segment: ["overlapping_periods"])
      expect(result.billing_segments).to eq([])
      expect(card.reload.next_billing_at).to eq(timestamp)
    end

    it "rejects a different window with the same starting boundary" do
      BillingSegment.sole.update!(started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 20))

      expect(result).to be_failure
      expect(result.error.messages).to eq(billing_segment: ["overlapping_periods"])
      expect(card.reload.next_billing_at).to eq(timestamp)
    end
  end

  context "when updating the clock fails" do
    before do
      allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **arguments|
        allow(arguments.fetch(:contract_rate_card)).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(card))
        original.call(**arguments)
      end
    end

    it "rolls back the inserted segment" do
      expect { result }.not_to change(BillingSegment, :count)
      expect(result).to be_failure
      expect(result.billing_segments).to eq([])
      expect(card.reload.next_billing_at).to eq(timestamp)
    end
  end

  context "with concurrent runs for the same customer", transaction: false do
    it "serializes production and advances the clock only once" do
      customer_id = customer.id
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(customer: Customer.find(customer_id), timestamp:)
          end
        end
      end
      results = threads.map(&:value)

      expect(results).to all(be_success)
      expect(results.flat_map(&:billing_segments).size).to eq(1)
      expect(card.billing_segments.count).to eq(1)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with an existing transaction", transaction: false do
    it "rolls back the customer's partial production even when the caller commits" do
      other_rate_card = create(:rate_card, organization:)
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
        next_billing_at: timestamp, id: "ffffffff-ffff-ffff-ffff-ffffffffffff")

      ActiveRecord::Base.transaction do
        expect(result).to be_failure
      end

      expect(BillingSegment.count).to eq(0)
      expect(result.billing_segments).to eq([])
      expect(card.reload.next_billing_at).to eq(timestamp)
    end
  end
end
