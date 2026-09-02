# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverEventJob do
  let(:customer) { create(:customer) }
  let(:event_type) { "customer_usage.refreshed" }

  describe "uniqueness" do
    let(:other_customer) { create(:customer) }

    # The read-time version in the payload is only a valid ordering token while deliveries
    # for one customer cannot overlap.
    it "serializes deliveries per customer" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilAndWhileExecuting)

      job = described_class.new(event_type, customer)
      same_customer_job = described_class.new(event_type, customer)
      other_customer_job = described_class.new(event_type, other_customer)

      expect(same_customer_job.lock_key).to eq(job.lock_key)
      expect(other_customer_job.lock_key).not_to eq(job.lock_key)
    end
  end

  describe "#perform" do
    before { allow(EventDestinations::CustomerUsage::RefreshedService).to receive(:call) }

    it "dispatches to the registered service" do
      described_class.perform_now(event_type, customer)

      expect(EventDestinations::CustomerUsage::RefreshedService).to have_received(:call).with(object: customer)
    end

    it "raises for an unregistered event type" do
      expect { described_class.perform_now("nope.nope", customer) }.to raise_error(KeyError)
    end
  end
end
