# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::DeliverJob do
  let(:destination) { create(:kinesis_destination) }
  let(:payload) { {webhook_type: "subscription.updated", emitted_at: "2026-08-31T12:00:00.000Z"} }
  let(:partition_key) { "cust_external_id" }

  it "delegates to the service the destination names, staying provider-blind" do
    allow(StreamingDestinations::Kinesis::DeliverService)
      .to receive(:call).and_return(BaseService::Result.new)

    described_class.perform_now(destination:, payload:, partition_key:)

    expect(StreamingDestinations::Kinesis::DeliverService).to have_received(:call).with(
      destination:, payload:, partition_key:
    )
  end

  it "does not raise when the delivery fails permanently, to avoid a retry storm" do
    failed = BaseService::Result.new.service_failure!(code: "record_too_large", message: "too big")
    allow(StreamingDestinations::Kinesis::DeliverService).to receive(:call).and_return(failed)

    expect { described_class.perform_now(destination:, payload:, partition_key:) }.not_to raise_error
  end

  it "runs on the webhook queue" do
    expect(described_class.new.queue_name).to eq("webhook")
  end
end
