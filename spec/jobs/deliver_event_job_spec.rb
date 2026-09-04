# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverEventJob, type: :job do
  let(:customer) { create(:customer) }

  it "runs on the dedicated queue" do
    expect(described_class.new.queue_name).to eq("streaming")
  end

  it "calls the service registered for the event type" do
    allow(EventDestinations::CustomerUsage::RefreshedService).to receive(:call)

    described_class.perform_now("customer_usage.refreshed", customer)

    expect(EventDestinations::CustomerUsage::RefreshedService).to have_received(:call).with(object: customer)
  end

  it "raises on an unregistered event type" do
    expect { described_class.perform_now("customer_usage.imagined", customer) }.to raise_error(KeyError)
  end

  describe "uniqueness" do
    it "locks per customer and event type" do
      key = described_class.new("customer_usage.refreshed", customer).lock_key

      expect(described_class.new("customer_usage.refreshed", customer).lock_key).to eq(key)
      expect(described_class.new("customer_usage.refreshed", create(:customer)).lock_key).not_to eq(key)
    end

    it "releases the enqueue lock before executing, so a refresh landing mid-delivery is not lost" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilAndWhileExecuting)
    end
  end
end
