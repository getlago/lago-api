# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementUpdateService do
  subject(:result) do
    described_class.call(
      subscription:,
      feature_code: feature_code,
      privilege_params: privilege_params,
      partial: partial
    )
  end

  # let, not let_it_be: the lock example commits its rows and empties the tables.
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }

  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }

  let(:feature_code) { feature.code }
  let(:privilege_params) { {"max" => 25} }
  let(:partial) { false }

  before do
    feature
    privilege
  end

  describe "#call", :premium do
    context "when successful" do
      let(:plan_entitlement) { create(:entitlement, organization:, plan:, feature: feature) }

      before do
        plan_entitlement

        allow(Entitlement::SubscriptionEntitlementCoreUpdateService).to receive(:call!).and_return(true)
      end

      it "calls the inner service with expected arguments" do
        result

        expect(Entitlement::SubscriptionEntitlementCoreUpdateService).to have_received(:call!).with(
          subscription: subscription,
          plan: plan, # no parent plan created here, so it's the subscription plan
          feature: feature,
          plan_entitlement:,
          sub_entitlement: nil,
          privilege_params: privilege_params.with_indifferent_access,
          partial: false
        )
      end

      it "sends `subscription.updated` webhook" do
        expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
      end

      it "produces an activity log" do
        subject
        expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
      end

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when another connection holds the subscription lock", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before { subscription }

      # Frees the lock holder left waiting by a failed expectation.
      after { release << -> {} }

      it "waits until the lock is released, then reads the entitlement written under it" do
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

        writer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(subscription: Subscription.find(subscription.id), feature_code:, privilege_params:, partial:)
          end
        end
        expect(writer.join(0.5)).to be_nil

        release << -> { create(:entitlement, organization:, plan: nil, subscription:, feature:) }
        holder.join
        expect(writer.value).to be_success
        sub_entitlement = Entitlement::Entitlement.where(subscription_id: subscription.id, entitlement_feature_id: feature.id).sole
        expect(sub_entitlement.values.sole.value).to eq("25")
      end
    end

    context "when a concurrent request creates the same entitlement" do
      before do
        # The concurrent request inserts its row after this one read the subscription entitlement.
        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken feature" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(feature: ["value_already_exist"])
        expect(subscription.entitlements.count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued
        expect(Utils::ActivityLog).not_to have_produced("subscription.updated")
      end
    end

    context "when a concurrent request creates the same entitlement value" do
      let(:sub_entitlement) { create(:entitlement, organization:, plan: nil, subscription:, feature:) }

      before do
        sub_entitlement

        # The concurrent request read the subscription entitlement before this one inserted its value.
        allow(Entitlement::SubscriptionEntitlementCoreUpdateService).to receive(:call!).and_wrap_original do |original, **kwargs|
          stale_entitlement = Entitlement::Entitlement.includes(values: :privilege).find(kwargs[:sub_entitlement].id)
          original.call(**kwargs)
          original.call(**kwargs, sub_entitlement: stale_entitlement)
        end
      end

      it "returns the validation error of a taken privilege" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(privilege: ["value_already_exist"])
        expect(sub_entitlement.values.count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when a concurrent request removes the same plan privilege" do
      let(:reset_privilege) { create(:privilege, organization:, feature:, code: "reset", value_type: "boolean") }
      let(:plan_entitlement) { create(:entitlement, organization:, plan:, feature:) }

      before do
        create(:entitlement_value, entitlement: plan_entitlement, privilege:, value: "10", organization:)
        create(:entitlement_value, entitlement: plan_entitlement, privilege: reset_privilege, value: true, organization:)

        allow(Entitlement::SubscriptionFeatureRemoval).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken privilege" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(privilege: ["value_already_exist"])
        expect(subscription.entitlement_removals.count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when another unique index refuses the write" do
      before do
        allow(Entitlement::Entitlement).to receive(:create!) do
          create(:plan, organization:).update_column(:code, plan.code) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it "raises the error" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique, /index_plans_on_organization_id_and_code/)
      end
    end

    context "when subscription is nil" do
      let(:subscription) { nil }

      it "returns not found failure for subscription" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when feature is not found" do
      let(:feature_code) { "nonexistent_feature" }

      it "returns not found failure for feature and does not call inner service" do
        allow(Entitlement::SubscriptionEntitlementCoreUpdateService).to receive(:call!).and_return(true)
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
        expect(Entitlement::SubscriptionEntitlementCoreUpdateService).not_to have_received(:call!)
      end
    end

    context "when privilege is not found" do
      before do
        allow(Entitlement::SubscriptionEntitlementCoreUpdateService).to receive(:call!).and_raise(
          ActiveRecord::RecordNotFound.new("Couldn't find Entitlement::Privilege")
        )
      end

      it "returns not found failure for privilege" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end

    context "when value is invalid" do
      let(:privilege_params) do
        {
          "max" => "invalid"
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({max_privilege_value: ["value_is_invalid"]})
      end
    end
  end
end
