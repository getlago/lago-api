# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeaturePrivilegeRemoveService do
  subject(:result) { described_class.call(subscription:, feature_code:, privilege_code:) }

  # let, not let_it_be: the concurrency examples commit their rows and empty the tables.
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "test_feature") }
  let(:privilege) { create(:privilege, feature:, code: "max") }
  let(:feature_code) { feature.code }
  let(:privilege_code) { privilege.code }

  describe "#call", :premium do
    context "when subscription is nil" do
      let(:subscription) { nil }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("subscription")
      end
    end

    context "when feature is not found" do
      let(:feature_code) { "nonexistent_feature" }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when privilege is not found" do
      let(:privilege_code) { "nonexistent_privilege" }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
      end
    end

    context "when privilege is not on subscription or plan" do
      before { privilege }

      it "succeeds and returns feature code" do
        expect(result).to be_success
        expect(result.feature_code).to eq(feature_code)
        expect(result.privilege_code).to eq(privilege_code)
      end

      it "does not create subscription feature removal" do
        expect { result }.not_to change(subscription.entitlement_removals, :count)
      end

      it "sends webhook" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
      end

      it "produces an activity log" do
        result
        expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
      end
    end

    context "when privilege is on plan but not on subscription" do
      let(:plan_entitlement) { create(:entitlement, feature:, plan:) }
      let(:plan_value) { create(:entitlement_value, entitlement: plan_entitlement, value: 100, privilege:) }

      before { plan_value }

      it "creates a subscription privilege removal" do
        expect { result }.to change(subscription.entitlement_removals.where(privilege:), :count).from(0).to(1)

        expect(result).to be_success

        removal = subscription.entitlement_removals.sole
        expect(removal.organization).to eq(organization)
        expect(removal.privilege).to eq(privilege)
      end

      context "when privilege is already removed" do
        it "succeeds" do
          create(:subscription_feature_removal, subscription:, privilege:)
          expect { result }.not_to change(subscription.entitlement_removals.where(privilege:), :count)
          expect(result).to be_success
        end
      end
    end

    context "when privilege is on subscription" do
      let(:subscription_entitlement) { create(:entitlement, feature:, subscription:, plan: nil) }
      let(:entitlement_value) { create(:entitlement_value, entitlement: subscription_entitlement, privilege:, value: "10") }

      before do
        entitlement_value
      end

      it "succeeds and returns feature code" do
        expect(result).to be_success
        expect(result.feature_code).to eq(feature_code)
        expect(result.privilege_code).to eq(privilege_code)
      end

      it "soft deletes the entitlement values" do
        expect { result }.to change { entitlement_value.reload.deleted_at }.from(nil)
      end

      it "does not discards the subscription entitlement" do
        expect { result }.not_to change { subscription_entitlement.reload.discarded? }
      end
    end

    context "when another connection holds the subscription lock", transaction: false do
      let(:subscription_entitlement) { create(:entitlement, feature:, subscription:, plan: nil) }
      let(:entitlement_value) { create(:entitlement_value, entitlement: subscription_entitlement, privilege:, value: "10") }
      let(:plan_entitlement) { create(:entitlement, feature:, plan:) }
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before do
        entitlement_value
        plan_entitlement
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << true }

      it "waits for the lock, then removes the privilege" do
        holder = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              Subscription.lock("FOR NO KEY UPDATE").find(subscription.id)
              locked << true
              release.pop
            end
          end
        end
        locked.pop

        remover = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(subscription: Subscription.find(subscription.id), feature_code:, privilege_code:)
          end
        end
        expect(remover.join(0.5)).to be_nil

        release << true
        holder.join

        expect(remover.value).to be_success
        expect(entitlement_value.reload.deleted_at).to be_present
        expect(Entitlement::SubscriptionFeatureRemoval.where(subscription:, privilege:).count).to eq(1)
      end
    end
  end
end
