# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advance standard pricing across rate changes" do
  subject(:fees) do
    travel_to(cycle_started_at + 5.minutes) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "advance-standard-contract",
          external_customer_id: customer.external_id,
          plan_code: "standard-plan",
          started_at: cycle_started_at.iso8601
        }})
      end

      # Contract creation schedules the initial R1 row before later rates are known.
    end

    rate_changes.each do |change|
      travel_to(change.fetch(:added_at)) do
        api_call(perform_jobs: false) do
          post_with_token(organization, "/api/v2/rate_cards/standard-card/rates", {rate: {
            code: change.fetch(:code),
            effective_from: change.fetch(:effective_at).iso8601,
            rate_model: "standard",
            billing_interval_unit: "month",
            rate_properties: {amount: change.fetch(:amount)}
          }})
        end
      end
    end

    rejected_rate_response if rejected_rate_params

    event_inputs.each do |event_input|
      travel_to(event_input.fetch(:received_at, event_input.fetch(:at))) do
        create_event({
          external_contract_id: contract.external_id,
          code: billable_metric.code,
          timestamp: event_input.fetch(:at).utc.strftime("%s.%6N"),
          properties: {"quantity" => event_input.fetch(:quantity)}
        }, perform_jobs: false)
        # Processing a stored segment is a separate lifecycle from event-time invoicing.
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end
    end

    Fee.where(contract:, fee_type: :product).order(:created_at).to_a
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "standard-customer") }
  let(:billable_metric) { organization.billable_metrics.find_by!(code: "standard-usage") }
  let(:contract) { organization.contracts.find_by!(external_id: "advance-standard-contract") }
  let(:rate_card) { organization.rate_cards.find_by!(code: "standard-card") }
  let(:first_rate) { rate_card.rates.find_by!(code: "r1") }
  let(:second_rate) { rate_card.rates.find_by!(code: "r2") }
  let(:third_rate) { rate_card.rates.find_by!(code: "r3") }
  let(:cycle_started_at) { Time.zone.parse("2027-01-01 00:00:00") }
  let(:cycle_ended_at) { Time.zone.parse("2027-02-01 00:00:00") }
  let(:initial_rate_start) { cycle_started_at }
  let(:second_rate_start) { Time.zone.parse("2027-01-20 00:00:00") }
  let(:rate_changes) do
    [{code: "r2", added_at: Time.zone.parse("2027-01-05 00:00:00"), effective_at: second_rate_start, amount: "2"}]
  end
  let(:event_inputs) { [{at: Time.zone.parse("2027-01-16 12:00:00"), quantity: 10}] }
  let(:rejected_rate_params) { nil }
  let(:rejected_rate_response) do
    travel_to(Time.zone.parse("2027-01-25 12:00:00")) do
      api_call(perform_jobs: false, raise_on_error: false) do
        post_with_token(organization, "/api/v2/rate_cards/standard-card/rates", {rate: rejected_rate_params})
      end
      [response.status, json]
    end
  end

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    create_or_update_customer({external_id: "standard-customer", name: "Standard customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Standard usage", code: "standard-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Standard usage", code: "standard-product", product_type: "metered", billable_metric_code: billable_metric.code
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Advance standard", code: "standard-card", product_code: "standard-product", currency: "USD",
        billing_timing: "advance", proration: false, display_on_invoice: true,
        rates: [{
          code: "r1", effective_from: initial_rate_start.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount: "1"}
        }]
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Standard plan", code: "standard-plan", currency: "USD"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/standard-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "standard-card"}
      })
    end
  end

  it "keeps a future rate off T6's event while shortening its fee period" do
    expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([[first_rate, 1_000, 10]])
    expect(fees.sole.properties).to include(
      "from_datetime" => cycle_started_at.iso8601(6),
      "to_datetime" => BillingSegment.inclusive_end(second_rate_start).iso8601(6)
    )
    expect(BillingSegment.where(contract:, cycle_started_at:).pluck(:rate_card_rate_id, :ended_at)).to eq([
      [first_rate.id, BillingSegment.inclusive_end(cycle_ended_at)]
    ])
    expect(fees.sole.invoice).to be_finalized
    expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(1)
  end

  context "when Z4's first rate begins after the event" do
    let(:initial_rate_start) { second_rate_start }
    let(:rate_changes) { [] }

    it "accepts the event without a priced product fee or invoice" do
      expect(fees).to eq([])
      expect(Event.where(organization:, external_subscription_id: contract.external_id).count).to eq(1)
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(0)
      expect(rate_card.rates.pluck(:id)).to eq([first_rate.id])
    end
  end

  context "when R5 attempts to append a backdated third rate" do
    let(:second_rate_start) { Time.zone.parse("2027-01-15 00:00:00") }
    let(:event_inputs) { [{at: Time.zone.parse("2027-01-26 12:00:00"), quantity: 10}] }
    let(:rejected_rate_params) do
      {code: "r3", effective_from: Time.zone.parse("2027-01-12").iso8601,
       rate_model: "standard", billing_interval_unit: "month", rate_properties: {amount: "3"}}
    end

    it "rejects R3 and invoices the following event at the surviving R2 price" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([[second_rate, 2_000, 10]])
      expect(rejected_rate_response.first).to eq(422)
      expect(rejected_rate_response.last.to_s).to include("must_not_be_before_today")
      expect(rate_card.rates.order(:effective_from).pluck(:code)).to eq(%w[r1 r2])
      expect(fees.sole.properties).to include(
        "from_datetime" => second_rate_start.iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)
      )
      expect(fees.sole.invoice).to be_finalized
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(1)
    end
  end

  context "when T3's pre-noon event arrives after the noon rate change and later event" do
    let(:second_rate_start) { Time.zone.parse("2027-01-15 12:00:00") }
    let(:rate_changes) do
      [{code: "r2", added_at: second_rate_start, effective_at: second_rate_start, amount: "2"}]
    end
    let(:event_inputs) do
      [
        {at: Time.zone.parse("2027-01-15 14:24:00"), quantity: 10},
        {at: Time.zone.parse("2027-01-15 06:00:00"), received_at: Time.zone.parse("2027-01-15 18:00:00"), quantity: 10}
      ]
    end

    it "prices by event instant while retaining the noon service boundary" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([
        [second_rate, 2_000, 10], [first_rate, 1_000, 10]
      ])
      expect(fees.map { |fee| [fee.properties["from_datetime"], fee.properties["to_datetime"]] }).to eq([
        [second_rate_start.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)],
        [cycle_started_at.iso8601(6), BillingSegment.inclusive_end(second_rate_start).iso8601(6)]
      ])
      expect(fees.map(&:invoice_id).uniq.size).to eq(2)
      expect(fees.map { |fee| fee.invoice.status }).to eq(%w[finalized finalized])
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(2)
    end
  end

  context "when B11's events cross the monthly cycle boundary" do
    let(:second_rate_start) { Time.zone.parse("2027-01-15 00:00:00") }
    let(:event_inputs) do
      [
        {at: Time.zone.parse("2027-01-31 23:59:59"), quantity: 80},
        {at: cycle_ended_at, quantity: 40}
      ]
    end

    it "resets the usage window and creates a new February invoice" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([
        [second_rate, 16_000, 80], [second_rate, 8_000, 40]
      ])
      expect(fees.map { |fee| [fee.properties["from_datetime"], fee.properties["to_datetime"]] }).to eq([
        [second_rate_start.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)],
        [cycle_ended_at.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at.next_month).iso8601(6)]
      ])
      expect(fees.map(&:invoice_id).uniq.size).to eq(2)
      expect(fees.map { |fee| fee.invoice.status }).to eq(%w[finalized finalized])
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(2)
    end
  end

  context "when T1's event falls between two rate changes" do
    let(:second_rate_start) { Time.zone.parse("2027-01-10 00:00:00") }
    let(:third_rate_start) { Time.zone.parse("2027-01-20 00:00:00") }
    let(:rate_changes) do
      [
        {code: "r2", added_at: Time.zone.parse("2027-01-02"), effective_at: second_rate_start, amount: "2"},
        {code: "r3", added_at: Time.zone.parse("2027-01-03"), effective_at: third_rate_start, amount: "3"}
      ]
    end

    it "uses R2 and saves T1's Jan 10–20 service window" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([[second_rate, 2_000, 10]])
      expect(fees.sole.properties).to include(
        "from_datetime" => second_rate_start.iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(third_rate_start).iso8601(6)
      )
      expect(fees.sole.invoice).to be_finalized
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(1)
    end

    context "when A1 sends events across all three rate windows" do
      let(:event_inputs) do
        [
          {at: Time.zone.parse("2027-01-05 12:00:00"), quantity: 10},
          {at: Time.zone.parse("2027-01-15 12:00:00"), quantity: 10},
          {at: Time.zone.parse("2027-01-25 12:00:00"), quantity: 10}
        ]
      end

      it "issues three invoices for R1, R2, and R3 without rewriting the stored R1 row" do
        expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([
          [first_rate, 1_000, 10], [second_rate, 2_000, 10], [third_rate, 3_000, 10]
        ])
        expect(fees.map { |fee| [fee.properties["from_datetime"], fee.properties["to_datetime"]] }).to eq([
          [cycle_started_at.iso8601(6), BillingSegment.inclusive_end(second_rate_start).iso8601(6)],
          [second_rate_start.iso8601(6), BillingSegment.inclusive_end(third_rate_start).iso8601(6)],
          [third_rate_start.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)]
        ])
        expect(fees.map(&:invoice_id)).to eq(fees.map(&:invoice_id).uniq)
        expect(fees.map { |fee| [fee.invoice&.status, fee.invoice&.fees&.count] }).to eq([
          ["finalized", 1], ["finalized", 1], ["finalized", 1]
        ])
        expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(3)
        expect(BillingSegment.where(contract:, cycle_started_at:).pluck(:rate_card_rate_id, :ended_at)).to eq([
          [first_rate.id, BillingSegment.inclusive_end(cycle_ended_at)]
        ])
      end
    end
  end

  context "when standard A5 sends three events across R2's activation" do
    let(:second_rate_start) { Time.zone.parse("2027-01-15 00:00:00") }
    let(:event_inputs) do
      [
        {at: Time.zone.parse("2027-01-10 12:00:00"), quantity: 80},
        {at: Time.zone.parse("2027-01-20 12:00:00"), quantity: 40},
        {at: Time.zone.parse("2027-01-25 12:00:00"), quantity: 30}
      ]
    end

    it "issues one invoice per event at its rate without repricing the earlier fee" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents, fee.units] }).to eq([
        [first_rate, 8_000, 80], [second_rate, 8_000, 40], [second_rate, 6_000, 30]
      ])
      expect(fees.map { |fee| [fee.properties["from_datetime"], fee.properties["to_datetime"]] }).to eq([
        [cycle_started_at.iso8601(6), BillingSegment.inclusive_end(second_rate_start).iso8601(6)],
        [second_rate_start.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)],
        [second_rate_start.iso8601(6), BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)]
      ])
      expect(fees.map(&:invoice_id)).to eq(fees.map(&:invoice_id).uniq)
      expect(fees.map { |fee| [fee.invoice&.status, fee.invoice&.fees&.count] }).to eq([
        ["finalized", 1], ["finalized", 1], ["finalized", 1]
      ])
      expect(Invoice.where(customer:, invoice_type: :subscription).count).to eq(3)
      expect(fees.first.reload.amount_cents).to eq(8_000)
    end
  end
end
