# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::SubscriptionCopyLockService do
  let(:lock_service) { described_class.new(subscription:, timeout_seconds:) }
  let(:subscription) { create(:subscription) }
  let(:timeout_seconds) { 5.seconds }
  let(:lock_key) { "billing-engine-migration-subscription-#{subscription.id}" }

  describe "#call" do
    it "holds an advisory lock on the subscription while the block runs" do
      expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false

      lock_service.call do
        expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be true
      end

      expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false
    end

    it "does not take the V1 subscription lock" do
      lock_service.call do
        expect(ActiveRecord::Base.advisory_lock_exists?("subscription-#{subscription.id}")).to be false
      end
    end

    context "when another copy of the subscription holds the lock", transaction: false do
      let(:timeout_seconds) { 0.seconds }

      around do |test|
        with_advisory_lock(lock_key, lock_released_after: 2.seconds) do
          test.run
        end
      end

      it "raises a BaseLockService::FailedToAcquireLock error" do
        expect { lock_service.call { nil } }
          .to raise_error(BaseLockService::FailedToAcquireLock, "Failed to acquire lock #{lock_key}")
      end
    end
  end
end
