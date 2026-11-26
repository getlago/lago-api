# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementUpdateService, transaction: false do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }

  before do
    privilege
    subscription
  end

  def write(subscription_record, value)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(
          subscription: subscription_record,
          feature_code: feature.code,
          privilege_params: {privilege.code => value},
          partial: true
        )
      end
    end
  end

  # Runs the block in another connection once the writer holds the subscription lock, before it locks the feature.
  def after_subscription_lock(subscription_record, &block)
    allow(subscription_record).to receive(:lock!).and_wrap_original do |original, *args|
      original.call(*args).tap do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.join(5)
      end
    end
  end

  describe "#call", :premium do
    it "refuses a write adding a feature deleted after it locked the subscription" do
      feature_id = feature.id
      subscription_record = Subscription.find(subscription.id)
      deleted = Queue.new
      after_subscription_lock(subscription_record) do
        deleted << Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
      end

      writer = write(subscription_record, 20)
      expect(writer.join(5)).to eq(writer)
      result = writer.value

      expect(deleted.pop(timeout: 1)).to be_success
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("feature")
      expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
      expect(SendWebhookJob).not_to have_been_enqueued.with("subscription.updated", anything)
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

      writer = write(Subscription.find(subscription.id), 20)
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

      writer = write(Subscription.find(subscription.id), 20)
      expect(writer.join(5)).to eq(writer)
      expect(deleter.join(5)).to eq(deleter)

      expect(blocked.pop(timeout: 1)).to be(true)
      expect(writer.value).to be_success
      expect(deleter.value).to be_success
      expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
    end

    # The writer holds the feature when it reaches the value insert. The privilege delete runs from another
    # connection there, given a bounded time: it either commits first, or waits for the writer and discards its value.
    # The entitlement exists already: inserting it would key-share lock the feature and make the delete wait anyway.
    it "leaves no live value on a privilege deleted while a write sets it" do
      create(:entitlement, organization:, plan: nil, subscription:, feature:)
      privilege_id = privilege.id
      deleter = nil

      # The core service builds the value through the entitlement's association, which calls new.
      allow(Entitlement::EntitlementValue).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        deleter ||= Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Entitlement::PrivilegeDestroyService.call(privilege: Entitlement::Privilege.find(privilege_id))
          end
        end
        deleter.join(1)
        original.call(*args, **kwargs)
      end

      writer = write(Subscription.find(subscription.id), 20)
      expect(writer.join(5)).to eq(writer)
      expect(deleter.join(5)).to eq(deleter)

      expect(writer.value).to be_success
      expect(deleter.value).to be_success
      expect(Entitlement::Privilege.with_discarded.find(privilege_id)).to be_discarded
      expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege_id).count).to eq(0)
    end
  end
end
