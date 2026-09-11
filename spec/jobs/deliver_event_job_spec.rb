# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverEventJob, type: :job do
  let(:customer) { create(:customer) }

  it "runs on the dedicated queue" do
    expect(described_class.new.queue_name).to eq("streaming")
  end

  it "calls the service registered for the event type" do
    allow(EventDestinations::CustomerUsage::RefreshedService).to receive(:call)

    described_class.perform_now("customer_usage.refreshed.v1", customer)

    expect(EventDestinations::CustomerUsage::RefreshedService).to have_received(:call).with(object: customer)
  end

  it "raises on an unregistered event type" do
    expect { described_class.perform_now("customer_usage.imagined.v1", customer) }.to raise_error(KeyError)
  end

  describe "uniqueness" do
    it "locks per customer and event type" do
      key = described_class.new("customer_usage.refreshed.v1", customer).lock_key

      expect(described_class.new("customer_usage.refreshed.v1", customer).lock_key).to eq(key)
      expect(described_class.new("customer_usage.refreshed.v1", create(:customer)).lock_key).not_to eq(key)
    end

    it "releases the enqueue lock before executing, so a refresh landing mid-delivery can still be queued" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilAndWhileExecuting)
    end

    it "drops a delivery that overlaps a running one, emitting no record" do
      allow(EventDestinations::CustomerUsage::RefreshedService).to receive(:call)
      job = described_class.new("customer_usage.refreshed.v1", customer)
      contend_on_runtime_lock(job)

      job.perform_now

      expect(EventDestinations::CustomerUsage::RefreshedService).not_to have_received(:call)
    end

    it "runs when no other delivery for the customer holds the runtime lock" do
      allow(EventDestinations::CustomerUsage::RefreshedService).to receive(:call)

      described_class.new("customer_usage.refreshed.v1", customer).perform_now

      expect(EventDestinations::CustomerUsage::RefreshedService).to have_received(:call).with(object: customer)
    end

    it "logs the drop in the shape the monitors match on" do
      allow(Rails.logger).to receive(:info)
      job = described_class.new("customer_usage.refreshed.v1", customer)
      contend_on_runtime_lock(job)

      job.perform_now

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/outcome=superseded event_type=customer_usage\.refreshed\.v1 customer_id=#{customer.id}/)
      )
    end
  end

  # The global test lock manager always grants a lock, so contention has to be forced. Only the
  # outcome of the runtime lock is faked: the gem's own strategy still decides what to do with it.
  def contend_on_runtime_lock(job)
    manager = instance_double(ActiveJob::Uniqueness::LockManager, delete_lock: true, delete_locks: true)
    allow(manager).to receive(:lock) { |resource, _ttl| resource != job.runtime_lock_key }
    allow(ActiveJob::Uniqueness).to receive(:lock_manager).and_return(manager)
  end
end
