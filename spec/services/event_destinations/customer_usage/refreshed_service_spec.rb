# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsage::RefreshedService do
  subject(:service) { described_class.new(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:producer) { instance_double(EventDestinations::KinesisProducer, produce: nil) }

  before do
    subscription
    allow(EventDestinations::KinesisProducer).to receive(:new).and_return(producer)
  end

  context "when the organization has no destination" do
    it "delivers nothing" do
      expect(service.call).to be_success
      expect(EventDestinations::KinesisProducer).not_to have_received(:new)
    end
  end

  context "when the organization has a destination" do
    let!(:destination) { create(:kinesis_destination, organization:) }

    it "delivers one record per active subscription" do
      service.call

      expect(producer).to have_received(:produce).once
    end

    it "builds the producer for the organization's destination" do
      service.call

      expect(EventDestinations::KinesisProducer).to have_received(:new).with(destination:)
    end

    it "partitions on the customer's external id" do
      service.call

      expect(producer).to have_received(:produce).with(hash_including(partition_key: customer.external_id))
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
          schema_version: described_class::SCHEMA_VERSION,
          event_type: "customer_usage.refreshed",
          object_type: "customer_usage",
          organization_id: organization.id,
          customer_external_id: customer.external_id,
          subscription_external_id: subscription.external_id
        )
      end

      it "carries a UUIDv7 event id" do
        expect(envelope[:event_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/)
      end

      it "carries a fixed-width UTC version with microseconds" do
        expect(envelope[:version]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
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
        expect(Rails.logger).to have_received(:error).with(a_string_matching(/failed for subscription/))
      end
    end

    it "logs and skips a subscription whose usage cannot be computed" do
      allow(Invoices::CustomerUsageService).to receive(:call).and_return(
        BaseService::Result.new.tap { it.not_found_failure!(resource: "customer") }
      )
      allow(Rails.logger).to receive(:warn)

      expect(service.call).to be_success
      expect(producer).not_to have_received(:produce)
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/skipped for subscription/))
    end
  end
end
