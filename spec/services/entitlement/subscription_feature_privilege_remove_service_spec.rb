# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeaturePrivilegeRemoveService do
  subject(:result) { described_class.call(owner: subscription, feature_code:, privilege_code:) }

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
      let(:entitlement_value) { create(:entitlement_value, entitlement: subscription_entitlement, privilege:, value: "10", updated_at: 1.day.ago) }

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

      it "sets updated_at on the discarded entitlement values" do
        freeze_time do
          result

          expect(entitlement_value.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
        end
      end

      it "does not discards the subscription entitlement" do
        expect { result }.not_to change { subscription_entitlement.reload.discarded? }
      end
    end

    context "when another connection holds the subscription lock", transaction: false do
      let(:plan_entitlement) { create(:entitlement, feature:, plan:) }
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before do
        subscription
        privilege
        plan_entitlement
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << -> {} }

      it "waits for the lock, then removes the privilege and the value written under it" do
        holder = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              Subscription.lock("FOR NO KEY UPDATE").find(subscription.id)
              locked << true
              release.pop.call
            end
          end
        end
        locked.pop

        remover = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(owner: Subscription.find(subscription.id), feature_code:, privilege_code:)
          end
        end
        expect(remover.join(0.5)).to be_nil

        # The holder commits an entitlement value that the remover can only see once it has the lock.
        release << lambda {
          sub_entitlement = create(:entitlement, organization:, feature:, subscription:, plan: nil)
          create(:entitlement_value, entitlement: sub_entitlement, privilege:, value: "10")
        }
        holder.join

        expect(remover.value).to be_success
        expect(Entitlement::EntitlementValue.unscoped.where(entitlement_privilege_id: privilege.id).sole.deleted_at).to be_present
        expect(Entitlement::SubscriptionFeatureRemoval.where(subscription:, privilege:).count).to eq(1)
      end
    end
  end

  describe "#call with a contract owner" do
    subject(:result) { described_class.call(owner: contract, feature_code:, privilege_code:) }

    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }
    let(:contract_value) { create(:entitlement_value, entitlement: contract_entitlement, privilege:, value: "5") }

    before do
      create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:)
      contract_value
    end

    it "discards the override value and stores a privilege removal on the contract" do
      expect(result).to be_success
      expect(Entitlement::EntitlementValue.with_discarded.find(contract_value.id)).to be_discarded
      expect(contract.entitlement_removals.reload.map { [it.entitlement_feature_id, it.entitlement_privilege_id] }).to eq([[nil, privilege.id]])
    end

    it "keeps one removal when called twice" do
      described_class.call(owner: contract, feature_code:, privilege_code:)

      expect(result).to be_success
      expect(contract.entitlement_removals.reload.count).to eq(1)
    end

    it "sends no subscription webhook" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
    end

    context "with a terminated contract" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

      it "refuses the write" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(base: ["contract_not_editable"])
        expect(contract_value.reload).not_to be_discarded
      end
    end
  end
end
