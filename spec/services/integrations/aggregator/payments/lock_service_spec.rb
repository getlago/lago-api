# frozen_string_literal: true

require "rails_helper"

describe Integrations::Aggregator::Payments::LockService do
  let(:lock_service) { described_class.new(payment:, timeout_seconds:, transaction: false) }
  let(:payment) { create(:payment) }
  let(:timeout_seconds) { 5.seconds }
  let(:lock_key) { "accounting-payment-sync-#{payment.id}" }

  describe "#call" do
    context "when lock can be acquired" do
      it "takes an advisory lock" do
        expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false

        lock_service.call do
          expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be true
        end

        expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false
      end

      it "exposes the block return value on the result" do
        expect(lock_service.call { :done }.value).to eq(:done)
      end
    end

    context "when lock cannot be acquired", transaction: false do
      let(:timeout_seconds) { 0.seconds }

      around do |test|
        with_advisory_lock(lock_key, lock_released_after: 2.seconds) do
          test.run
        end
      end

      it "raises a BaseLockService::FailedToAcquireLock error" do
        expect do
          lock_service.call { nil }
        end.to raise_error(BaseLockService::FailedToAcquireLock, "Failed to acquire lock #{lock_key}")
      end
    end
  end
end
