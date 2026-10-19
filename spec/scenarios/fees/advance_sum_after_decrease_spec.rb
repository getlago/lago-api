# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advance SUM billing after a usage decrease" do
  let(:started_at) { Time.zone.parse("2026-10-06 00:00:00") }
  let(:event_values) { [300, 700, -300, 400] }
  let(:inputs) do
    event_values.each_with_index.map do |value, index|
      {transaction_id: "advance-sum-event-#{index + 1}", at: started_at + (index + 1).hours, value: value.to_s}
    end
  end

  shared_examples "billing usage after a decrease" do
    it "bills the decrease according to the billing source and charges new usage above the maximum" do
      fees = event_fees

      expect(fees.map(&:amount_cents)).to eq(expected_amounts)
      expect(fees.map { |fee| fee.invoice.total_amount_cents }).to eq(expected_amounts)
      expect(fees.third.amount_details).to include(
        "fixed_fee_total_amount" => expected_fixed_fee,
        "paid_events" => expected_paid_events
      )
      expect(fees.map { |fee| fee.invoice.status }).to eq(["finalized"] * 4)
      expect(fees.sum { |fee| fee.invoice.total_amount_cents }).to eq(expected_amounts.sum)
    end
  end

  context "with legacy subscription charges" do
    subject(:event_fees) do
      inputs.each do |input|
        travel_to(input.fetch(:at))
        create_event({
          code: billable_metric.code,
          transaction_id: input.fetch(:transaction_id),
          external_subscription_id: subscription.external_id,
          timestamp: input.fetch(:at).to_i,
          properties: {units: input.fetch(:value)}
        })
      end

      events = Event.where(organization:, transaction_id: inputs.map { |input| input.fetch(:transaction_id) })
        .order(:timestamp).to_a
      fees_by_event = Fee.where(subscription:, charge:, pay_in_advance_event_id: events.map(&:id))
        .index_by(&:pay_in_advance_event_id)
      events.map { |event| fees_by_event[event.id] }
    end

    let(:organization) { create(:organization, feature_flags: [], webhook_url: nil) }
    let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
    let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD", pay_in_advance: false) }
    let(:subscription) { customer.subscriptions.sole }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "units") }
    let(:expected_amounts) { [780, 1780, 30, 280] }
    let(:expected_fixed_fee) { "0.3" }
    let(:expected_paid_events) { "1.0" }
    let(:charge) do
      create(
        :percentage_charge,
        :pay_in_advance,
        invoiceable: true,
        plan:,
        billable_metric:,
        properties: {rate: "2.5", fixed_amount: "0.30"}
      )
    end

    around do |example|
      travel_to(started_at) { example.run }
    end

    before do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "advance-sum-legacy-subscription",
        plan_code: plan.code,
        billing_time: "anniversary"
      })
      charge
    end

    it_behaves_like "billing usage after a decrease"

    context "when non-recurring SUM usage rebounds below the billed maximum" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "units") }
      let(:event_values) { [100, -30, 20] }

      it "charges the fixed fee for the decrease and the positive rebound" do
        fees = event_fees

        expect(fees.map(&:amount_cents)).to eq([280, 30, 30])
        expect(fees.map { |fee| fee.invoice.total_amount_cents }).to eq([280, 30, 30])
        expect(fees.map { |fee| fee.invoice.status }).to eq(["finalized"] * 3)
        expect(fees.last).to have_attributes(units: 20)
        expect(fees.last.amount_details).to include(
          "fixed_fee_total_amount" => "0.3",
          "paid_events" => "1.0"
        )
        expect(CachedAggregation.where(charge:, external_subscription_id: subscription.external_id)
          .order(:timestamp).pluck(:current_aggregation, :max_aggregation)).to eq([[100, 100], [70, 100], [90, 100]])
      end
    end
  end

  context "with contract product-catalog billing" do
    subject(:event_fees) do
      inputs.each do |input|
        travel_to(input.fetch(:at))
        create_event({
          external_contract_id: contract.external_id,
          code: billable_metric.code,
          transaction_id: input.fetch(:transaction_id),
          timestamp: input.fetch(:at).to_i,
          properties: {units: input.fetch(:value)}
        }, perform_jobs: false)
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end

      Fee.where(contract:, fee_type: :product).order(:created_at).to_a
    end

    let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
    let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
    let(:contract) do
      create(:contract, organization:, customer:, started_at:, billing_time: :anniversary,
        billing_entity: customer.billing_entity)
    end
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "units") }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, currency: "USD", billing_timing: :advance,
        display_on_invoice: true)
    end
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, rate_model: :percentage,
        rate_properties: {"rate" => "2.5", "fixed_amount" => "0.30"})
    end
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: started_at.to_date,
        billing_anchor_date: started_at.to_date, next_billing_at: started_at)
    end
    let(:expected_amounts) { [780, 1780, 0, 280] }
    let(:expected_fixed_fee) { "0.0" }
    let(:expected_paid_events) { "0.0" }

    around do |example|
      travel_to(started_at + 12.hours) { example.run }
    end

    before do
      rate_card_rate
      contract_rate_card
    end

    it_behaves_like "billing usage after a decrease"

    context "when non-recurring SUM usage rebounds below the billed maximum" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "units") }
      let(:event_values) { [100, -30, 20] }

      it "keeps the product fixed fee suppressed until the billed maximum is exceeded" do
        fees = event_fees

        expect(fees.map(&:amount_cents)).to eq([280, 0, 0])
        expect(fees.map { |fee| fee.invoice.total_amount_cents }).to eq([280, 0, 0])
        expect(fees.last).to have_attributes(units: 20)
        expect(fees.last.amount_details).to include(
          "fixed_fee_total_amount" => "0.0",
          "paid_events" => "0.0"
        )
      end
    end
  end
end
