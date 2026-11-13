# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementsUpdateService, transaction: false do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:other_subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:locked) { Queue.new }
  let(:release) { Queue.new }

  before do
    privilege
    subscription
    other_subscription
  end

  # Frees a lock holder left waiting by a failed expectation.
  after { release << -> {} }

  def write(subscription_id, value)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(
          subscription: Subscription.find(subscription_id),
          entitlements_params: {feature.code => {privilege.code => value}},
          partial: true
        )
      end
    end
  end

  # Holds the subscription row lock in another connection until `release` receives the block to run before the commit.
  def hold_subscription_lock(subscription_id)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          Subscription.lock("FOR NO KEY UPDATE").find(subscription_id)
          locked << true
          release.pop.call
        end
      end
    end
  end

  describe "#call", :premium do
    # Both writers must have read the subscription entitlements before either inserts. Each one waits at the insert
    # for the other to arrive, for a bounded time, so a writer serialized behind the other does not hang.
    it "serializes two concurrent writes adding the same feature on one subscription" do
      arrived = Queue.new

      allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        arrived << true
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep 0.05 while arrived.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        original.call(*args, **kwargs)
      end

      results = [write(subscription.id, 10), write(subscription.id, 20)].map(&:value)

      expect(results).to all(be_success)
      expect(Entitlement::Entitlement.where(subscription_id: subscription.id, entitlement_feature_id: feature.id).count).to eq(1)
    end

    it "makes a write on the locked subscription wait, and not a write on another subscription" do
      holder = hold_subscription_lock(subscription.id)
      locked.pop

      other_writer = write(other_subscription.id, 10)
      expect(other_writer.join(5)).to eq(other_writer)
      expect(other_writer.value).to be_success

      writer = write(subscription.id, 20)
      expect(writer.join(0.5)).to be_nil

      release << -> {}
      holder.join
      expect(writer.value).to be_success
      expect(Entitlement::Entitlement.where(subscription_id: subscription.id, entitlement_feature_id: feature.id).count).to eq(1)
    end

    context "when the subscription is terminated" do
      let(:subscription) { create(:subscription, :terminated, organization:, customer:, plan:) }

      it "stores the write" do
        result = write(subscription.id, 10).value

        expect(result).to be_success
        expect(Entitlement::Entitlement.where(subscription_id: subscription.id, entitlement_feature_id: feature.id).count).to eq(1)
      end
    end
  end
end
