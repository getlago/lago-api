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

  def write(subscription_id, value, subscription_record: nil, partial: true)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(
          subscription: subscription_record || Subscription.find(subscription_id),
          entitlements_params: {feature.code => {privilege.code => value}},
          partial:
        )
      end
    end
  end

  # Runs the block in another connection once the writer holds the subscription lock, before it locks the features.
  def after_subscription_lock(subscription_record, &block)
    allow(subscription_record).to receive(:lock!).and_wrap_original do |original, *args|
      original.call(*args).tap do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.join(5)
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

    it "refuses a write adding a feature deleted after it locked the subscription" do
      feature_id = feature.id
      subscription_record = Subscription.find(subscription.id)
      deleted = Queue.new
      after_subscription_lock(subscription_record) do
        deleted << Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
      end

      writer = write(subscription.id, 20, subscription_record:)
      expect(writer.join(5)).to eq(writer)
      result = writer.value

      expect(deleted.pop(timeout: 1)).to be_success
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("feature")
      expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
    end

    context "with a full replace omitting a feature of the plan and of the subscription" do
      let(:other_feature) { create(:feature, organization:) }
      let(:other_privilege) { create(:privilege, organization:, feature: other_feature, code: "limit", value_type: "integer") }
      let(:sub_entitlement) { create(:entitlement, organization:, plan: nil, subscription:, feature: other_feature) }
      let(:sub_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: other_privilege, value: "10", organization:) }

      before do
        create(:entitlement, organization:, plan:, feature: other_feature)
        sub_value
      end

      it "stores nothing when the added feature is deleted after it locked the subscription" do
        feature_id = feature.id
        subscription_record = Subscription.find(subscription.id)
        deleted = Queue.new
        after_subscription_lock(subscription_record) do
          deleted << Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
        end

        writer = write(subscription.id, 20, subscription_record:, partial: false)
        expect(writer.join(5)).to eq(writer)
        result = writer.value

        expect(deleted.pop(timeout: 1)).to be_success
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(Entitlement::SubscriptionFeatureRemoval.where(subscription_id: subscription.id).count).to eq(0)
        expect(sub_entitlement.reload.deleted_at).to be_nil
        expect(sub_value.reload.deleted_at).to be_nil
        expect(SendWebhookJob).not_to have_been_enqueued.with("subscription.updated", anything)
      end
    end

    # The writer has read the feature when it reaches the insert. The delete runs from another connection
    # there, given a bounded time: it either commits first, or waits for the writer and discards what it wrote.
    it "leaves no live entitlement on a feature deleted while a write adds it" do
      feature_id = feature.id
      deleter = nil

      allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        deleter ||= Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
          end
        end
        deleter.join(1)
        original.call(*args, **kwargs)
      end

      writer = write(subscription.id, 20)
      expect(writer.join(5)).to eq(writer)
      expect(deleter.join(5)).to eq(deleter)

      expect(deleter.value).to be_success
      expect(Entitlement::Feature.with_discarded.find(feature_id)).to be_discarded
      expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
    end

    # The writer holds the feature lock when it reaches the insert, after it read the feature. The delete starts
    # there and must wait for the writer to commit, then discards what it wrote.
    it "makes a feature delete wait for a write that read the feature" do
      feature_id = feature.id
      deleter = nil
      blocked = Queue.new

      allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        deleter ||= Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
          end
        end
        blocked << deleter.join(0.5).nil?
        original.call(*args, **kwargs)
      end

      writer = write(subscription.id, 20)
      expect(writer.join(5)).to eq(writer)
      expect(deleter.join(5)).to eq(deleter)

      expect(blocked.pop(timeout: 1)).to be(true)
      expect(writer.value).to be_success
      expect(deleter.value).to be_success
      expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
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
