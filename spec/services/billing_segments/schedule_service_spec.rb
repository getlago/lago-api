# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ScheduleService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 15)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, proration: true) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1)) }
  let(:timestamp) { Time.utc(2026, 2, 1) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 15), billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.utc(2026, 1, 15))
  end

  before do
    rate
    card
  end

  it "persists the calendar's priced segment and advances the clock" do
    expect(result).to be_success
    segment = result.billing_segments.sole.reload

    expect(segment).to have_attributes(
      organization_id: organization.id, customer_id: customer.id, contract_id: contract.id,
      contract_rate_card_id: card.id, rate_card_rate_id: rate.id, rate_override_id: nil,
      rate_properties: {"amount" => "10"}, currency: "EUR", pricing_unit_id: nil,
      status: "pending", invoice_id: nil,
      cycle_started_at: Time.utc(2026, 1, 15), started_at: Time.utc(2026, 1, 15),
      ended_at: BillingSegment.inclusive_end(Time.utc(2026, 2, 1)), billing_at: Time.utc(2026, 2, 1)
    )
    expect(segment.proration_ratio).to be_within(1e-10).of(17.fdiv(31))
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  it "returns no new segments when the same timestamp is retried" do
    first = result.billing_segments.sole
    retry_result = described_class.call(customer:, timestamp:)

    expect(retry_result).to be_success
    expect(retry_result.billing_segments).to eq([])
    expect(card.billing_segments.reload).to eq([first])
  end

  it "does not rewrite an existing snapshot or status when the clock is stale" do
    first = result.billing_segments.sole
    first.update!(status: :done)
    card.update!(next_billing_at: Time.utc(2026, 1, 15))
    rate.update!(rate_properties: {"amount" => "99"})

    retry_result = described_class.call(customer:, timestamp:)

    expect(retry_result).to be_success
    expect(retry_result.billing_segments).to eq([])
    expect(first.reload).to have_attributes(status: "done", rate_properties: {"amount" => "10"})
    expect(card.billing_segments.count).to eq(1)
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  it "recovers all due periods after a delayed run" do
    catch_up = described_class.call(customer:, timestamp: Time.utc(2026, 4, 15))

    expect(catch_up).to be_success
    expect(catch_up.billing_segments.map(&:billing_at))
      .to eq([Time.utc(2026, 2, 1), Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)])
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 5, 1))
  end

  it "respects the initial clock when a backdated contract joins a later period" do
    card.update!(next_billing_at: Time.utc(2026, 4, 1))

    catch_up = described_class.call(customer:, timestamp: Time.utc(2026, 5, 1))

    expect(catch_up).to be_success
    expect(catch_up.billing_segments.map(&:started_at)).to eq([Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)])
  end

  it "does not persist an arrears segment before it is due" do
    early = described_class.call(customer:, timestamp: Time.utc(2026, 1, 20))

    expect(early).to be_success
    expect(early.billing_segments).to eq([])
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
  end

  context "without proration" do
    let(:rate_card) { create(:rate_card, organization:, product:, proration: false) }

    it "stores a full-price ratio even for a partial first period" do
      segment = result.billing_segments.sole

      expect(segment.duration_in_days).to eq(17)
      expect(segment.proration_ratio).to eq(1)
    end
  end

  context "with concurrent runs for the same customer", transaction: false do
    it "persists each due segment once and advances the clock once" do
      customer_id = customer.id
      run_at = timestamp
      ready = Queue.new
      start = Queue.new

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            described_class.call!(customer: Customer.find(customer_id), timestamp: run_at)
          end
        end
      end

      results = Timeout.timeout(10) do
        2.times { ready.pop }
        2.times { start << true }
        threads.map(&:value)
      end

      expect(results.map { it.billing_segments.size }.sort).to eq([0, 1])
      expect(card.billing_segments.count).to eq(1)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    ensure
      threads&.each { it.kill if it.alive? }
      threads&.each(&:join)
    end
  end

  context "with a bounded introductory phase" do
    let(:override) do
      create(:rate_override, organization:, billing_interval_count: 1, billing_interval_unit: "week",
        rate_properties: {"amount" => "3"})
    end

    before do
      card.update!(billing_anchor_date: card.effective_date)
      create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card,
        position: 1, code: "intro", billing_interval_cycle_count: 2, rate_override: override)
    end

    it "resumes through a phase transition with the correct cadence and price" do
      first = described_class.call!(customer:, timestamp: Time.utc(2026, 1, 22)).billing_segments.sole
      later = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 28)).billing_segments

      expect([first, *later].map { [it.started_at, it.billing_at, it.rate_override_id] }).to eq([
        [Time.utc(2026, 1, 15), Time.utc(2026, 1, 22), override.id],
        [Time.utc(2026, 1, 22), Time.utc(2026, 1, 29), override.id],
        [Time.utc(2026, 1, 29), Time.utc(2026, 2, 28), nil]
      ])
      expect(later.map(&:rate_properties)).to eq([{"amount" => "3"}, {"amount" => "10"}])
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 29))
    end
  end

  it "excludes other customers, unsigned contracts, discarded cards and future clocks" do
    card.update!(next_billing_at: Time.utc(2026, 3, 1))
    other_customer = create(:customer, organization:)
    other_contract = create(:contract, organization:, customer: other_customer, started_at: contract.started_at)
    create(:contract_rate_card, organization:, contract: other_contract, rate_card:, **card.attributes.slice(
      "effective_date", "billing_anchor_date"
    ), next_billing_at: Time.utc(2026, 1, 15))

    %i[pending canceled].each do |status|
      unsigned = create(:contract, organization:, customer:, status:, started_at: contract.started_at)
      create(:contract_rate_card, organization:, contract: unsigned, rate_card:,
        effective_date: card.effective_date, next_billing_at: Time.utc(2026, 1, 15))
    end
    discarded = create(:contract_rate_card, organization:, contract:, next_billing_at: Time.utc(2026, 1, 15))
    discarded.discard!

    expect(result).to be_success
    expect(result.billing_segments).to eq([])
    expect(BillingSegment.count).to eq(0)
  end

  context "with a rate change inside the cycle" do
    let!(:next_rate) do
      create(:rate_card_rate, organization:, rate_card:,
        effective_from: Time.utc(2026, 1, 20), rate_properties: {"amount" => "20"})
    end

    it "resumes a partly persisted cycle without duplicating its first segment" do
      first_run = described_class.call(customer:, timestamp: Time.utc(2026, 1, 20))
      first = first_run.billing_segments.sole
      expect(first.rate_card_rate).to eq(rate)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))

      second = result.billing_segments.sole
      expect(second.rate_card_rate).to eq(next_rate)
      expect(second.started_at).to eq(BillingSegment.exclusive_end(first.ended_at))
      expect([first.cycle_started_at, second.cycle_started_at]).to eq([Time.utc(2026, 1, 15)] * 2)
      expect([first.duration_in_days, second.duration_in_days]).to eq([5, 12])
      expect(card.billing_segments.count).to eq(2)
    end
  end

  context "with advance billing" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, proration: true) }
    let(:timestamp) { Time.utc(2026, 1, 15) }

    it "persists the segment when it opens, with its future service end" do
      segment = result.billing_segments.sole

      expect(segment.billing_at).to eq(timestamp)
      expect(segment.ended_at).to eq(BillingSegment.inclusive_end(Time.utc(2026, 2, 1)))
      expect(segment.proration_ratio).to be_within(1e-10).of(17.fdiv(31))
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end

    context "when the initial clock is the signing instant inside the segment" do
      let(:timestamp) { Time.utc(2026, 1, 15, 12) }

      before do
        contract.update!(started_at: timestamp)
        card.update!(next_billing_at: timestamp)
      end

      it "includes the advance segment serving that instant" do
        segment = result.billing_segments.sole

        expect(segment.started_at).to eq(Time.utc(2026, 1, 15))
        expect(segment.billing_at).to eq(Time.utc(2026, 1, 15))
        expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      end
    end

    it "does not recover advance periods before a backdated contract's initial clock" do
      card.update!(next_billing_at: Time.utc(2026, 3, 15, 12))

      catch_up = described_class.call(customer:, timestamp: Time.utc(2026, 4, 1))

      expect(catch_up.billing_segments.map(&:billing_at)).to eq([Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)])
    end
  end

  context "with an override and a pricing unit" do
    let(:pricing_unit) { create(:pricing_unit, organization:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, proration: true, applied_pricing_unit_code: pricing_unit.code)
    end
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2025, 1, 1),
        applied_pricing_unit_conversion_rate: 2)
    end
    let(:override) do
      create(:rate_override, organization:, rate_properties: {"amount" => "3"}, pricing_unit_conversion_rate: 4)
    end

    before do
      create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card,
        position: 1, code: "intro", rate_override: override)
    end

    it "stores the effective price and keeps both pricing references" do
      segment = result.billing_segments.sole

      expect(segment).to have_attributes(rate_card_rate_id: rate.id, rate_override_id: override.id,
        pricing_unit_id: pricing_unit.id, currency: "EUR", rate_properties: {"amount" => "3"})
      expect(segment.pricing_unit_conversion_rate).to eq(4)
    end

    it "fails without advancing the clock if the configured pricing unit no longer exists" do
      pricing_unit.update!(code: "renamed_unit")
      original_clock = card.next_billing_at

      expect(result).not_to be_success
      expect(result.error.error_code).to eq("pricing_unit_not_found")
      expect(result.billing_segments).to eq([])
      expect(card.billing_segments.count).to eq(0)
      expect(card.reload.next_billing_at).to eq(original_clock)
    end
  end

  context "when the card has ended" do
    before { card.update!(ended_date: Date.new(2026, 1, 20)) }

    it "recovers the last arrears segment and clears the exhausted clock" do
      segment = result.billing_segments.sole

      expect(segment.ended_at).to eq(BillingSegment.inclusive_end(Time.utc(2026, 1, 21)))
      expect(segment.billing_at).to eq(Time.utc(2026, 1, 21))
      expect(segment.proration_ratio).to be_within(1e-10).of(6.fdiv(31))
      expect(card.reload.next_billing_at).to be_nil
      expect(described_class.call(customer:, timestamp: Time.utc(2026, 3, 1)).billing_segments).to eq([])
    end
  end

  context "when the contract has terminated" do
    before { contract.update!(status: :terminated, ended_at: Time.utc(2026, 1, 20, 12)) }

    it "keeps the exact service end and the calendar's consumed days" do
      segment = result.billing_segments.sole

      expect(segment.ended_at).to eq(BillingSegment.inclusive_end(contract.ended_at))
      expect(segment.proration_ratio).to be_within(1e-10).of(6.fdiv(31))
      expect(card.reload.next_billing_at).to be_nil
    end
  end

  it "recovers the final arrears segment when termination precedes the saved clock" do
    described_class.call!(customer:, timestamp: Time.utc(2026, 1, 20))
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    contract.update!(status: :terminated, ended_at: Time.utc(2026, 1, 25, 12))

    segment = result.billing_segments.sole

    expect(segment.billing_at).to eq(contract.ended_at)
    expect(segment.ended_at).to eq(BillingSegment.inclusive_end(contract.ended_at))
    expect(card.reload.next_billing_at).to be_nil
  end

  it "recovers an inclusive card end that precedes the saved clock" do
    described_class.call!(customer:, timestamp: Time.utc(2026, 1, 20))
    card.update!(ended_date: Date.new(2026, 1, 25))

    segment = result.billing_segments.sole

    expect(segment.billing_at).to eq(Time.utc(2026, 1, 26))
    expect(segment.proration_ratio).to be_within(1e-10).of(11.fdiv(31))
    expect(card.reload.next_billing_at).to be_nil
  end

  context "when the period crosses daylight saving time" do
    let(:customer) { create(:customer, organization:, timezone: "Europe/Paris") }
    let(:timestamp) { Time.utc(2026, 3, 31, 22) }

    before do
      card.update!(effective_date: Date.new(2026, 3, 1), billing_anchor_date: Date.new(2026, 3, 1),
        next_billing_at: Time.utc(2026, 2, 28, 23))
    end

    it "stores local-month boundaries without changing the number of billable days" do
      segment = result.billing_segments.sole

      expect(segment.started_at).to eq(Time.utc(2026, 2, 28, 23))
      expect(segment.ended_at).to eq(BillingSegment.inclusive_end(timestamp))
      expect(segment.duration_in_days).to eq(31)
      expect(segment.proration_ratio).to eq(1)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 4, 30, 22))
    end
  end

  it "advances to the first billing date when pricing has not started yet" do
    rate.update!(effective_from: Time.utc(2026, 3, 1))

    expect(result).to be_success
    expect(result.billing_segments).to eq([])
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))
  end

  it "rolls back earlier segments and clocks when another card cannot be scheduled" do
    create(:contract_rate_card, id: "ffffffff-ffff-ffff-ffff-ffffffffffff", organization:, contract:,
      effective_date: card.effective_date, billing_anchor_date: card.billing_anchor_date,
      next_billing_at: card.next_billing_at)
    original_clock = card.next_billing_at

    expect(result).not_to be_success
    expect(result.error).to be_a(BaseService::NotFoundFailure)
    expect(result.error.error_code).to eq("rate_not_found")
    expect(result.billing_segments).to eq([])
    expect(card.billing_segments.count).to eq(0)
    expect(card.reload.next_billing_at).to eq(original_clock)
  end
end
