# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerFullUsage::RefreshedService do
  subject(:service) { described_class.new(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, code: "enterprise_monthly") }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: 6.months.ago) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let!(:charge) { create(:standard_charge, plan:, billable_metric:, organization:) }
  let(:producer) { instance_double(Lago::Kinesis::Producer, produce: nil) }
  let(:producer_calls) { [] }

  before do
    subscription
    allow(Lago::Kinesis::Producer).to receive(:new).and_return(producer)
    allow(producer).to receive(:produce) { |args| producer_calls << args }
  end

  context "when the organization has no destination" do
    it "delivers nothing" do
      expect(service.call).to be_success
      expect(producer_calls).to be_empty
    end
  end

  # full_usage is refused unless the organization has granular_lifetime_usage and a premium
  # license, so without this every delivery is silently skipped.
  context "when the organization has a destination", :premium do
    before do
      organization.update!(premium_integrations: ["granular_lifetime_usage"])
      create(:kinesis_destination, organization:)
    end

    it "asks for usage since the subscription started, in one call carrying every charge id" do
      allow(Invoices::CustomerUsageService).to receive(:call).and_call_original

      service.call

      expect(Invoices::CustomerUsageService).to have_received(:call).once.with(
        hash_including(
          usage_filters: an_object_having_attributes(
            full_usage: true,
            filter_by_charge_id: [charge.id]
          )
        )
      )
      expect(producer_calls.size).to eq(1)
    end

    it "delivers a snapshot whose window starts at subscription.started_at" do
      service.call

      usage = producer_calls.first[:data][:customer_usage]
      expect(Time.zone.parse(usage[:from_datetime])).to be_within(1.second).of(subscription.started_at)
    end

    it "attributes the usage across the customer's wallets, like the current period record does" do
      wallet = create(:wallet, customer:, organization:, currency: "EUR", priority: 10,
        ongoing_usage_balance_cents: 1500, credits_ongoing_usage_balance: "15.0")
      other = create(:wallet, customer:, organization:, currency: "EUR", priority: 50,
        ongoing_usage_balance_cents: 500, credits_ongoing_usage_balance: "5.0")

      service.call

      expect(producer_calls.first[:data][:customer_usage][:wallets]).to eq(
        [
          {lago_id: wallet.id, credits: "15.0", amount_cents: 1500, amount_currency: "EUR"},
          {lago_id: other.id, credits: "5.0", amount_cents: 500, amount_currency: "EUR"}
        ]
      )
    end

    context "with usage that a wallet absorbed" do
      let(:wallet) { create(:wallet, customer:, organization:, ongoing_billable_metric_amounts: {subscription.id => {billable_metric.id => 1_000_000}}) }

      before do
        wallet
        create(:event, organization:, subscription:, customer:, code: billable_metric.code)
        allow(EventDestinations::WalletAmountsService).to receive(:call!).and_call_original
      end

      it "attributes the charge to that wallet" do
        service.call

        expect(producer_calls.first[:data][:customer_usage][:charges_usage].map { it[:wallet_id] }).to eq([wallet.id])
      end

      it "counts what wallets paid since the subscription started, the window the record covers" do
        service.call

        expect(EventDestinations::WalletAmountsService).to have_received(:call!)
          .with(hash_including(subscription:, from_datetime: producer_calls.first[:data][:customer_usage][:from_datetime]))
      end
    end

    # Nothing stubbed but the producer: billing records what the first wallet paid, the refresh
    # records the next wallet taking over, and the lifetime record attributes each part.
    context "with an invoice paid by one wallet and ongoing usage on the next" do
      let!(:charge) { create(:standard_charge, plan:, billable_metric:, organization:, properties: {amount: "10"}) }
      let(:first_wallet) do
        create(:wallet, :with_inbound_transaction, customer:, organization:, priority: 1, balance_cents: 1000, credits_balance: 10.0)
      end
      let(:second_wallet) do
        create(:wallet, :with_inbound_transaction, customer:, organization:, priority: 2, balance_cents: 5000, credits_balance: 50.0)
      end
      let(:past_invoice) do
        create(:invoice, customer:, organization:, status: :finalized, currency: "EUR", total_amount_cents: 1000, taxes_amount_cents: 0)
      end

      before do
        first_wallet
        second_wallet
        create(:invoice_subscription, invoice: past_invoice, subscription:, charges_from_datetime: 5.months.ago)
        create(:charge_fee, invoice: past_invoice, subscription:, charge:, amount_cents: 1000, precise_amount_cents: 1000,
          taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        create(:event, organization:, subscription:, customer:, code: billable_metric.code, timestamp: 4.months.ago)
        create(:event, organization:, subscription:, customer:, code: billable_metric.code)
        Credits::AppliedPrepaidCreditsService.call!(invoice: past_invoice)
      end

      it "attributes each part of the lifetime usage to the wallet that covered it" do
        service.call

        entries = producer_calls.first[:data][:customer_usage][:charges_usage].map { it.slice(:wallet_id, :amount_cents) }

        expect(entries).to match_array([
          {wallet_id: first_wallet.id, amount_cents: 1000},
          {wallet_id: second_wallet.id, amount_cents: 1000}
        ])
      end
    end

    it "carries the full usage event type and the shared object type" do
      service.call

      expect(producer_calls.first[:data]).to include(
        event_type: "customer_full_usage.refreshed.v1",
        object_type: "customer_usage"
      )
    end

    context "when the plan is on the exclusion list" do
      before do
        destination = StreamingDestinations::BaseDestination.for_event(organization, described_class::EVENT_TYPE).first
        destination.customer_full_usage_excluded_plan_codes = ["enterprise_monthly"]
        destination.save!
      end

      it "delivers nothing for that subscription" do
        expect(service.call).to be_success
        expect(producer_calls).to be_empty
      end
    end

    context "when the plan carries a prorated charge" do
      before do
        recurring_metric = create(:billable_metric, organization:, recurring: true, aggregation_type: "sum_agg", field_name: "amount")
        create(:standard_charge, plan:, billable_metric: recurring_metric, organization:, prorated: true)
        allow(Rails.logger).to receive(:warn)
      end

      it "skips rather than raising, so the current period record is unaffected" do
        expect(service.call).to be_success
        expect(producer_calls).to be_empty
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/outcome=skipped/))
      end
    end
  end
end
