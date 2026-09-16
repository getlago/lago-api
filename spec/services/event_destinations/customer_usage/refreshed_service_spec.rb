# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsage::RefreshedService do
  subject(:service) { described_class.new(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:producer) { instance_double(Lago::Kinesis::Producer, produce: nil) }

  before do
    subscription
    allow(Lago::Kinesis::Producer).to receive(:new).and_return(producer)
    allow(StreamingDestinations::BaseDestination).to receive(:for_event).and_call_original
  end

  context "when the organization has no destination" do
    it "delivers nothing" do
      expect(service.call).to be_success
      expect(producer).not_to have_received(:produce)
    end
  end

  context "when the organization has a destination" do
    before { create(:kinesis_destination, organization:) }

    it "delivers one record per active subscription" do
      service.call

      expect(producer).to have_received(:produce).once
    end

    it "looks the destination up across every type, matching what the model validates" do
      service.call

      expect(StreamingDestinations::BaseDestination)
        .to have_received(:for_event).with(organization, "customer_usage.refreshed.v1")
    end

    it "partitions on the customer's external id" do
      service.call

      expect(producer).to have_received(:produce).with(hash_including(partition_key: customer.external_id))
    end

    describe "the wallets the usage is attributed to" do
      let(:producer_calls) { [] }

      before { allow(producer).to receive(:produce) { |args| producer_calls << args } }

      it "reports every active wallet in application order, not one picked by currency" do
        second = create(:wallet, customer:, organization:, currency: "EUR", priority: 50,
          ongoing_usage_balance_cents: 500, credits_ongoing_usage_balance: "5.0")
        first = create(:wallet, customer:, organization:, currency: "EUR", priority: 10,
          ongoing_usage_balance_cents: 1500, credits_ongoing_usage_balance: "15.0")

        described_class.new(object: customer).call

        expect(producer_calls.first[:data][:customer_usage][:wallets].map { it[:lago_id] })
          .to eq([first.id, second.id])
      end

      it "includes a wallet in another currency, since each entry names its own" do
        create(:wallet, customer:, organization:, currency: "USD", priority: 10,
          ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: "2.0")

        described_class.new(object: customer).call

        expect(producer_calls.first[:data][:customer_usage][:wallets].map { it[:amount_currency] })
          .to eq(["USD"])
      end

      # The refresh allocates across every subscription at once, so there is no per-subscription
      # share to report. Each record carries the same customer wide totals, deliberately.
      it "repeats the same customer totals on each subscription's record" do
        create(:wallet, customer:, organization:, currency: "EUR", priority: 10,
          ongoing_usage_balance_cents: 1500, credits_ongoing_usage_balance: "15.0")
        create(:subscription, customer:, plan: create(:plan, organization:))

        described_class.new(object: customer).call

        wallets = producer_calls.map { it[:data][:customer_usage][:wallets] }

        expect(wallets.size).to eq(2)
        expect(wallets.uniq.size).to eq(1)
        expect(wallets.first.sum { it[:amount_cents] }).to eq(1500)
      end
    end

    it "computes usage without taxes, so no tax provider is called on every refresh" do
      allow(Invoices::CustomerUsageService).to receive(:call).and_call_original

      service.call

      expect(Invoices::CustomerUsageService).to have_received(:call)
        .with(hash_including(apply_taxes: false, with_cache: true))
    end

    describe "the envelope" do
      subject(:envelope) do
        service.call
        producer_calls.first[:data]
      end

      let(:producer_calls) { [] }

      before do
        allow(producer).to receive(:produce) { |args| producer_calls << args }
      end

      it "carries the identifiers a consumer needs" do
        expect(envelope).to include(
          event_type: "customer_usage.refreshed.v1",
          object_type: "customer_usage",
          organization_id: organization.id,
          customer_external_id: customer.external_id,
          subscription_external_id: subscription.external_id
        )
      end

      it "emits the datetime formats the consumer parses" do
        usage = envelope[:customer_usage]

        expect(usage[:from_datetime]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        expect(usage[:to_datetime]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        expect(usage[:issuing_date]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
      end

      it "carries a UUIDv7 event id" do
        expect(envelope[:event_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/)
      end

      it "carries a fixed-width UTC version with microseconds" do
        expect(envelope[:version]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
      end
    end

    describe "when the caller supplies the usage it already computed" do
      let(:producer_calls) { [] }
      let(:precomputed) do
        Invoices::CustomerUsageService.call!(customer:, subscription:, usage_filters: UsageFilters::WITHOUT_PRESENTATION_FILTER).usage
      end

      before do
        allow(producer).to receive(:produce) { |args| producer_calls << args }
      end

      it "does not compute the usage again" do
        usage = precomputed
        allow(Invoices::CustomerUsageService).to receive(:call)

        described_class.new(object: customer, usages: {subscription => usage}).call

        expect(Invoices::CustomerUsageService).not_to have_received(:call)
        expect(producer).to have_received(:produce).once
      end

      it "produces the same envelope as computing it here would" do
        described_class.new(object: customer).call
        computed = producer_calls.first[:data]

        producer_calls.clear
        described_class.new(object: customer, usages: {subscription => precomputed}).call
        supplied = producer_calls.first[:data]

        expect(supplied.except(:event_id, :version)).to eq(computed.except(:event_id, :version))
      end

      it "falls back to computing a subscription the caller did not supply" do
        other = create(:subscription, customer:, plan: create(:plan, organization:))

        described_class.new(object: customer, usages: {subscription => precomputed}).call

        expect(producer_calls.map { it[:data][:subscription_external_id] })
          .to match_array([subscription.external_id, other.external_id])
      end
    end

    context "with several active subscriptions" do
      let(:other_subscription) { create(:subscription, customer:, plan: create(:plan, organization:)) }

      before { other_subscription }

      it "gives every subscription in one delivery the same version" do
        versions = []
        allow(producer).to receive(:produce) { |args| versions << args[:data][:version] }

        service.call

        expect(versions.size).to eq(2)
        expect(versions.uniq.size).to eq(1)
      end

      it "keeps one failing subscription from stopping the others" do
        call_count = 0
        allow(producer).to receive(:produce) do
          call_count += 1
          raise "boom" if call_count == 1
        end
        allow(Rails.logger).to receive(:error)

        expect(service.call).to be_success
        expect(call_count).to eq(2)
        expect(Rails.logger).to have_received(:error)
          .with(a_string_matching(/outcome=failed .*error=RuntimeError message=boom/))
      end
    end

    it "logs and skips a subscription whose usage cannot be computed" do
      allow(Invoices::CustomerUsageService).to receive(:call).and_return(
        BaseService::Result.new.tap { it.not_found_failure!(resource: "customer") }
      )
      allow(Rails.logger).to receive(:warn)

      expect(service.call).to be_success
      expect(producer).not_to have_received(:produce)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/outcome=skipped .*subscription_id=#{subscription.id}/))
    end
  end
end
