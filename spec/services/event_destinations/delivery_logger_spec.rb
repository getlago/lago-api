# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::DeliveryLogger do
  let(:destination) { create(:kinesis_destination) }

  before { allow(Rails.logger).to receive(:info).and_call_original }

  it "emits the destination and organization on every line" do
    described_class.emit(:delivered, destination:, partition_key: "cust_1")

    expect(Rails.logger).to have_received(:info).with(
      "[streaming] event=delivery outcome=delivered destination_id=#{destination.id} " \
      "organization_id=#{destination.organization_id} partition_key=cust_1"
    )
  end

  it "omits the destination when there is none to name" do
    described_class.emit(:superseded, customer_id: "cust_1")

    expect(Rails.logger).to have_received(:info).with(
      "[streaming] event=delivery outcome=superseded customer_id=cust_1"
    )
  end

  it "quotes a value that would otherwise break logfmt parsing" do
    allow(Rails.logger).to receive(:error)

    described_class.emit(:dropped, message: "User is not authorized to perform: kinesis:PutRecord")

    expect(Rails.logger).to have_received(:error).with(
      '[streaming] event=delivery outcome=dropped message="User is not authorized to perform: kinesis:PutRecord"'
    )
  end

  it "drops keys with no value rather than emitting an empty one" do
    described_class.emit(:delivered, partition_key: "cust_1", bytes: nil)

    expect(Rails.logger).to have_received(:info).with(
      "[streaming] event=delivery outcome=delivered partition_key=cust_1"
    )
  end

  it "logs each outcome at its own severity" do
    expect(described_class::OUTCOMES).to eq(
      delivered: :info, throttled: :error, dropped: :error,
      superseded: :info, skipped: :warn, failed: :error
    )
  end

  it "raises on an outcome it does not know, rather than logging something unmatchable" do
    expect { described_class.emit(:vanished) }.to raise_error(KeyError)
  end
end
