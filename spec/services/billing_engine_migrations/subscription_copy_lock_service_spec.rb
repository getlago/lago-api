# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::SubscriptionCopyLockService do
  let(:lock_service) { described_class.new(subscription:, timeout_seconds:) }
  let(:subscription) { create(:subscription) }
  let(:timeout_seconds) { 5.seconds }
  let(:lock_key) { "billing-engine-migration-subscription-#{subscription.organization_id}-#{subscription.external_id}" }

  describe "#call" do
    it "holds an advisory lock on the external id while the block runs" do
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

    it "shares the lock with the other subscriptions of the external id in the organization only" do
      previous_subscription = create(
        :subscription,
        :terminated,
        organization: subscription.organization,
        customer: subscription.customer,
        external_id: subscription.external_id
      )
      other_external_id_subscription = create(:subscription, organization: subscription.organization, customer: subscription.customer)
      other_organization_subscription = create(:subscription, external_id: subscription.external_id)

      lock_service.call do
        expect(described_class.new(subscription: previous_subscription)).to be_locked
        expect(described_class.new(subscription: other_external_id_subscription)).not_to be_locked
        expect(described_class.new(subscription: other_organization_subscription)).not_to be_locked
      end
    end

    context "when another copy of the external id holds the lock", transaction: false do
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
