# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsage::RefreshedService do
  subject(:result) { described_class.call(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

  let(:subscriptions) do
    [
      create(:subscription, organization:, customer:, started_at: 2.years.ago),
      create(:subscription, organization:, customer:, started_at: 1.year.ago)
    ]
  end

  # The real SDK client, stubbed: request parameters are still validated, nothing is sent.
  let(:aws_client) { Aws::Kinesis::Client.new(region: "eu-west-1", stub_responses: true) }
  let(:put_record_args) { [] }

  before do
    stub_const("ENV", ENV.to_h.merge(
      "LAGO_EVENT_DESTINATION_ORG_ID" => organization.id,
      "LAGO_EVENT_DESTINATION_TRANSPORT" => "log",
      "LAGO_EVENT_DESTINATION_KINESIS_STREAM_ARN" => "arn:aws:kinesis:eu-west-1:123456789012:stream/usage",
      "LAGO_EVENT_DESTINATION_KINESIS_REGION" => "eu-west-1"
    ))

    subscriptions.each do |subscription|
      create(:standard_charge, organization:, plan: subscription.plan, billable_metric:, properties: {amount: "3"})
    end

    create(:event, organization:, subscription: subscriptions.first, customer:, code: billable_metric.code)

    allow(Aws::Kinesis::Client).to receive(:new).and_return(aws_client)
    allow(aws_client).to receive(:put_record).and_wrap_original do |original, **args|
      put_record_args << args
      original.call(**args)
    end
  end

  describe "#call" do
    it "puts one record per active subscription" do
      expect(result).to be_success

      expect(aws_client).to have_received(:put_record).twice
    end

    it "targets the configured stream and partitions on the customer external id" do
      result

      expect(put_record_args.map { it[:stream_arn] }.uniq).to eq(["arn:aws:kinesis:eu-west-1:123456789012:stream/usage"])
      expect(put_record_args.map { it[:partition_key] }.uniq).to eq([customer.external_id])
    end

    it "writes a webhook-shaped envelope for each subscription" do
      result

      payloads = put_record_args.map { JSON.parse(it[:data]) }

      expect(payloads.map { it["subscription_external_id"] }).to match_array(subscriptions.map(&:external_id))

      payloads.each do |payload|
        expect(payload["webhook_type"]).to eq("customer_usage.refreshed")
        expect(payload["object_type"]).to eq("customer_usage")
        expect(payload["organization_id"]).to eq(organization.id)
        expect(payload["customer_external_id"]).to eq(customer.external_id)
        expect(payload["version"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
      end
    end

    it "stamps both records of a delivery with the same version" do
      result

      versions = put_record_args.map { JSON.parse(it[:data])["version"] }

      expect(versions.uniq.size).to eq(1)
    end

    it "serializes the usage with the public endpoint serializer" do
      result

      payloads = put_record_args.map { JSON.parse(it[:data]) }
      payload = payloads.find { it["subscription_external_id"] == subscriptions.first.external_id }

      usage = ::Invoices::CustomerUsageService.call(customer:, subscription: subscriptions.first, with_cache: true).usage
      expected = ::V1::Customers::UsageSerializer.new(usage, root_name: "customer_usage", includes: %i[charges_usage]).serialize

      expect(payload["customer_usage"]).to eq(JSON.parse(JSON.generate(expected)))
      expect(payload["customer_usage"]["charges_usage"]).to be_present
    end

    context "when no destination is configured for the organization" do
      before { stub_const("ENV", ENV.to_h.except("LAGO_EVENT_DESTINATION_ORG_ID")) }

      it "does not instantiate a client nor put any record" do
        expect(result).to be_success

        expect(Aws::Kinesis::Client).not_to have_received(:new)
        expect(aws_client).not_to have_received(:put_record)
      end
    end

    context "when the usage service fails" do
      before do
        allow(::Invoices::CustomerUsageService).to receive(:call)
          .and_return(BaseResult.new.tap { it.service_failure!(code: "boom", message: "boom") })
      end

      it "skips the subscription without raising" do
        expect { result }.not_to raise_error

        expect(aws_client).not_to have_received(:put_record)
      end
    end

    context "when a put fails" do
      before do
        failed = false
        allow(aws_client).to receive(:put_record) do
          next nil if failed

          failed = true
          raise Aws::Kinesis::Errors::ServiceError.new(nil, "boom")
        end
      end

      it "keeps publishing the remaining subscriptions and does not raise" do
        expect { result }.not_to raise_error

        expect(aws_client).to have_received(:put_record).twice
      end
    end
  end
end
