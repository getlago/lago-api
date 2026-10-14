# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract usage billing with duplicate percentage events" do
  subject(:event_fee_records) do
    inputs.each do |input|
      travel_to(input.fetch(:at) + 1.minute)
      create_event({
        external_contract_id: contract.external_id,
        code: billable_metric.code,
        transaction_id: input.fetch(:transaction_id),
        timestamp: input.fetch(:at).to_i,
        properties: {user_id: input.fetch(:user_id), operation_type: "add"}
      }, perform_jobs: false)
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
    end

    events = Event.where(organization:, transaction_id: inputs.map { |input| input.fetch(:transaction_id) })
      .order(:timestamp).to_a
    fees_by_event = Fee.where(contract:, fee_type: :product, pay_in_advance_event_id: events.map(&:id))
      .index_by(&:pay_in_advance_event_id)
    events.map { |event| [event, fees_by_event[event.id]] }
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
  let(:started_at) { Time.zone.parse("2026-10-07 00:00:00") }
  let(:contract) do
    create(:contract, organization:, customer:, started_at:, billing_time: :anniversary,
      billing_entity: customer.billing_entity)
  end
  let(:billable_metric) do
    create(:billable_metric, organization:, aggregation_type: :unique_count_agg, recurring: true, field_name: "user_id")
  end
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "USD", billing_timing: :advance,
      proration: false)
  end
  let(:rate) do
    RateCardRates::CreateService.call!(rate_card:, params: {
      code: "duplicate-percentage-rate", effective_from: started_at, rate_model: :percentage,
      rate_properties: {"rate" => "2.5", "fixed_amount" => "0.30"},
      billing_interval_unit: :month, billing_interval_count: 1
    }).rate_card_rate
  end
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: started_at.to_date, billing_anchor_date: started_at.to_date,
      next_billing_at: started_at)
  end
  let(:inputs) do
    [
      {transaction_id: "unique-percentage-a1", user_id: "A", at: started_at + 9.hours + 6.minutes + 17.seconds},
      {transaction_id: "unique-percentage-a2", user_id: "A", at: started_at + 9.hours + 6.minutes + 18.seconds},
      {transaction_id: "unique-percentage-b", user_id: "B", at: started_at + 9.hours + 6.minutes + 19.seconds}
    ]
  end

  around do |example|
    travel_to(started_at + 12.hours) { example.run }
  end

  before do
    rate
    card
  end

  it "does not charge a second fixed fee for a duplicate user event" do
    records = event_fee_records
    expect(records.map { |event, _fee| event.transaction_id }).to eq(inputs.map { |input| input.fetch(:transaction_id) })

    first_fee, duplicate_fee, distinct_fee = records.map(&:last)
    expect(first_fee).to have_attributes(units: 1, amount_cents: 33)
    expect(distinct_fee).to have_attributes(units: 1, amount_cents: 33)
    if duplicate_fee
      expect(duplicate_fee).to have_attributes(units: 0, amount_cents: 0)
    end

    invoices = records.filter_map(&:last).map(&:invoice).uniq
    expect(invoices).to all(have_attributes(status: "finalized"))
    expect(invoices.select { |invoice| invoice.total_amount_cents.positive? }.map(&:total_amount_cents)).to eq([33, 33])
    expect(invoices.sum(&:total_amount_cents)).to eq(66)
  end
end
