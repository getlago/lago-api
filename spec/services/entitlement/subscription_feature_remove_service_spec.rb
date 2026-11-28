# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeatureRemoveService do
  subject(:result) { described_class.call(owner: subscription, feature_code:) }

  # let, not let_it_be: the concurrency examples commit their rows and empty the tables.
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "test_feature") }
  let(:feature_code) { feature.code }

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

    context "when feature is not on subscription or plan" do
      before { feature }

      it "succeeds and returns feature code" do
        expect(result).to be_success
        expect(result.feature_code).to eq(feature_code)
      end

      it "does not create subscription feature removal" do
        expect { result }.not_to change(Entitlement::SubscriptionFeatureRemoval, :count)
      end

      it "sends webhook" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
      end

      it "produces an activity log" do
        result
        expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
      end
    end

    context "when feature is on plan but not on subscription" do
      let(:plan_entitlement) { create(:entitlement, feature:, plan:) }

      before { plan_entitlement }

      it "creates a subscription feature removal" do
        expect { result }.to change(organization.subscription_feature_removals, :count).by(1)

        expect(result).to be_success

        removal = Entitlement::SubscriptionFeatureRemoval.last
        expect(removal.organization).to eq(organization)
        expect(removal.subscription).to eq(subscription)
        expect(removal.feature).to eq(feature)
      end

      context "when the feature is already removed" do
        it "succeeds" do
          create(:subscription_feature_removal, subscription:, feature:)
          expect { result }.not_to change(subscription.entitlement_removals.where(feature:), :count)
          expect(result).to be_success
        end
      end
    end

    context "when feature is on subscription" do
      let(:subscription_entitlement) { create(:entitlement, feature:, subscription:, plan: nil) }
      let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
      let(:entitlement_value) { create(:entitlement_value, entitlement: subscription_entitlement, privilege:, value: "10", updated_at: 1.day.ago) }

      before do
        entitlement_value
        subscription_entitlement.reload
      end

      it "succeeds and returns feature code" do
        expect(result).to be_success
        expect(result.feature_code).to eq(feature_code)
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

      it "discards the subscription entitlement" do
        expect { result }.to change { subscription_entitlement.reload.discarded? }.from(false).to(true)
      end

      context "when feature is also on plan" do
        let(:privilege2) { create(:privilege, feature:, code: "max_admin", value_type: "integer") }
        let(:plan_entitlement) { create(:entitlement, feature:, plan:) }
        let(:plan_entitlement_value2) { create(:entitlement_value, privilege: privilege2, entitlement: plan_entitlement, value: "10") }
        let(:privilege_removal) { create(:subscription_feature_removal, privilege: privilege2, subscription:, updated_at: 1.day.ago) }

        before do
          plan_entitlement_value2
          privilege_removal
        end

        it "creates a subscription feature removal" do
          expect { result }.to change(organization.subscription_feature_removals.where(feature:), :count).by(1)

          removal = organization.subscription_feature_removals.order(created_at: :desc).first
          expect(removal.organization).to eq(organization)
          expect(removal.subscription).to eq(subscription)
          expect(removal.feature).to eq(feature)
        end

        it "soft deletes the entitlement values and discards entitlement" do
          expect { result }.to change { entitlement_value.reload.deleted_at }.from(nil)
            .and change { subscription_entitlement.reload.discarded? }.from(false).to(true)
        end

        it "cleans up existing privilege removals" do
          expect { result }.to change { privilege_removal.reload.discarded? }.from(false).to(true)
        end

        it "sets updated_at on the discarded privilege removals" do
          freeze_time do
            result

            expect(privilege_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
          end
        end
      end

      context "when plan has parent plan with the feature" do
        let(:parent_plan) { create(:plan, organization:) }
        let(:child_plan) { create(:plan, organization:, parent: parent_plan) }
        let(:subscription) { create(:subscription, organization:, customer:, plan: child_plan) }
        let(:parent_entitlement) { create(:entitlement, feature:, plan: parent_plan) }
        let(:subscription_entitlement) { create(:entitlement, feature:, subscription:, plan: nil) }

        before do
          parent_entitlement
          entitlement_value
          subscription_entitlement.reload
        end

        it "creates a subscription feature removal" do
          expect { result }.to change(Entitlement::SubscriptionFeatureRemoval, :count).by(1)

          removal = Entitlement::SubscriptionFeatureRemoval.last
          expect(removal.organization).to eq(organization)
          expect(removal.subscription).to eq(subscription)
          expect(removal.feature).to eq(feature)
        end
      end
    end

    context "when another connection holds the subscription lock", transaction: false do
      let(:plan_entitlement) { create(:entitlement, feature:, plan:) }
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before do
        subscription
        plan_entitlement
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << -> {} }

      it "waits for the lock, then removes the feature and the entitlement written under it" do
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
            described_class.call(owner: Subscription.find(subscription.id), feature_code:)
          end
        end
        expect(remover.join(0.5)).to be_nil

        # The holder commits an entitlement that the remover can only see once it has the lock.
        release << -> { create(:entitlement, organization:, feature:, subscription:, plan: nil) }
        holder.join

        expect(remover.value).to be_success
        expect(Entitlement::Entitlement.unscoped.where(subscription_id: subscription.id, entitlement_feature_id: feature.id).sole).to be_discarded
        expect(Entitlement::SubscriptionFeatureRemoval.where(subscription:, feature:).count).to eq(1)
      end
    end
  end

  describe "#call with a contract owner" do
    subject(:result) { described_class.call(owner: contract, feature_code:) }

    # The organization factory also creates a webhook endpoint.
    let(:organization) { create(:organization, feature_flags:) }
    let(:feature_flags) { %w[entitlement_events] }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "contract_123") }
    let(:max) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }

    before { feature }

    # The entitlement of the contract, in the v2 contract entitlement shape.
    def contract_entitlement_render(**fields)
      {lago_contract_id: contract.id, feature_code: "test_feature", **fields}
    end

    def sent_webhooks
      ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { it[:job] == SendWebhookJob }
        .map { ActiveJob::Arguments.deserialize(it[:args]) }
    end

    context "when the catalog plan grants the feature" do
      let(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: max, value: "20") }
      let(:sso) { create(:privilege, organization:, feature:, code: "sso", value_type: "boolean") }
      let(:privilege_removal) { create(:subscription_feature_removal, :contract, organization:, contract:, privilege: sso) }

      # sso is removed from the contract, so only max applies: 20 on the contract over 10 on the plan.
      let(:render) do
        contract_entitlement_render(source: "plan", values: [{privilege_code: "max", value: 20, plan_value: 10, source: "contract"}])
      end

      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: max, value: "10")
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: "true")
        contract_value
        privilege_removal
      end

      it "discards the override, its values and privilege removals, and stores a removal on the contract" do
        expect(result).to be_success
        expect(contract_entitlement.reload).to be_discarded
        expect(contract_value.reload).to be_discarded
        expect(privilege_removal.reload).to be_discarded
        expect(contract.entitlement_removals.reload.map { [it.entitlement_feature_id, it.entitlement_privilege_id] }).to eq([[feature.id, nil]])
        expect(Entitlement::SubscriptionFeatureRemoval.where(subscription_id: nil, contract_id: nil)).to be_empty
        expect(Entitlement::SubscriptionEntitlement.for_contract(contract)).to be_empty
      end

      it "returns the entitlement as it applied before the removal" do
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(render)
      end

      it "sends one contract_entitlement.deleted webhook and activity log with the entitlement before the removal" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob)
          .with("contract_entitlement.deleted", contract, {contract_entitlement: render})

        expect(sent_webhooks).to eq([["contract_entitlement.deleted", contract, {contract_entitlement: render}]])
        expect(Utils::ActivityLog).to have_received(:produce).with(
          contract, "contract_entitlement.deleted", after_commit: true,
          activity_object: render,
          changes: {"values" => [render[:values], nil]}
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args).once
        expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "subscription.updated", any_args)
      end

      context "when the feature is already removed" do
        before { described_class.call(owner: contract, feature_code:) }

        it "fails with a feature not found and sends nothing more" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("feature")
          expect(contract.entitlement_removals.reload.count).to eq(1)
          # The first removal only.
          expect(sent_webhooks.size).to eq(1)
          expect(Utils::ActivityLog).to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args).once
        end
      end

      context "without a webhook endpoint" do
        before { organization.webhook_endpoints.destroy_all }

        it "logs the removal and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(Utils::ActivityLog).to have_received(:produce).with(
            contract, "contract_entitlement.deleted", after_commit: true,
            activity_object: render,
            changes: {"values" => [render[:values], nil]}
          ).once
        end
      end

      context "without the entitlement_events feature flag" do
        let(:feature_flags) { [] }

        it "removes the feature, returns it and sends nothing" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(render)
          expect(contract_entitlement.reload).to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
        end
      end

      context "when the removal write fails" do
        before { allow(Entitlement::SubscriptionFeatureRemoval).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid) }

        it "rolls back the removal and sends nothing" do
          expect { result }.to raise_error(ActiveRecord::StatementInvalid)

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
          expect(contract_entitlement.reload).not_to be_discarded
        end
      end
    end

    context "when only the contract grants the feature" do
      let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: max, value: "20") }

      before { contract_value }

      it "discards the entitlement and its values, stores no removal and returns it" do
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(
          contract_entitlement_render(source: "contract", values: [{privilege_code: "max", value: 20, plan_value: nil, source: "contract"}])
        )
        expect(contract_entitlement.reload).to be_discarded
        expect(contract_value.reload).to be_discarded
        expect(contract.entitlement_removals).to be_empty
        expect(sent_webhooks.map(&:first)).to eq(["contract_entitlement.deleted"])
      end
    end

    context "when the feature does not apply to the contract" do
      it "fails with a feature not found and sends nothing" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
        expect(contract.entitlement_removals).to be_empty
        expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
      end
    end

    context "when only a legacy plan grants a feature with the same id" do
      before { create(:entitlement, organization:, feature:, plan:) }

      it "fails with a feature not found and stores no removal" do
        expect(result.error.resource).to eq("feature")
        expect(contract.entitlement_removals).to be_empty
      end
    end

    context "with a contract without a catalog plan" do
      let(:catalog_plan) { nil }
      let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }

      before do
        create(:entitlement, organization:, feature:, plan:)
        contract_entitlement
      end

      it "discards the contract entitlement and stores no removal" do
        expect(result).to be_success
        expect(contract_entitlement.reload).to be_discarded
        expect(contract.entitlement_removals).to be_empty
      end
    end

    %i[terminated canceled].each do |status|
      context "with a #{status} contract" do
        let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }

        before { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }

        it "refuses the write and sends nothing" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).not_to be_success
          expect(result.error.messages).to eq(base: ["contract_not_editable"])
          expect(contract.entitlement_removals).to be_empty
        end

        context "with an unknown feature" do
          let(:feature_code) { "unknown" }

          it "refuses the write as for a known feature" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq(base: ["contract_not_editable"])
          end
        end
      end
    end

    context "with an unknown feature" do
      let(:feature_code) { "unknown" }

      it "fails with a feature not found" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when the feature is deleted while the removal waits for it", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before do
        create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:)
        contract
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << true }

      it "fails with a feature not found, stores no removal and sends nothing" do
        deleter = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              Entitlement::Feature.lock.find(feature.id).discard!
              locked << true
              release.pop
            end
          end
        end
        locked.pop

        remover = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(owner: Contract.find(contract.id), feature_code:)
          end
        end
        # The removal found the feature before the delete committed, then waits on its lock.
        expect(remover.join(0.5)).to be_nil

        release << true
        deleter.join

        expect(remover.value.error.resource).to eq("feature")
        expect(Entitlement::SubscriptionFeatureRemoval.where(contract_id: contract.id, entitlement_feature_id: feature.id)).to be_empty
        expect(sent_webhooks).to be_empty
      end
    end

    context "with two concurrent removals of the same feature", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      # Committed before the threads start, which only read them.
      before do
        create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:)
        contract
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << true }

      it "removes it once, fails the other with a feature not found and sends one event" do
        holder = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              Contract.lock("FOR NO KEY UPDATE").find(contract.id)
              locked << true
              release.pop
            end
          end
        end
        locked.pop

        removers = Array.new(2) do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(owner: Contract.find(contract.id), feature_code:)
            end
          end
        end
        # Both removers wait on the lock, so each one reads the entitlements once it holds the lock.
        expect(removers.map { it.join(0.5) }).to eq([nil, nil])

        release << true
        holder.join
        results = removers.map(&:value)

        expect(results.count(&:success?)).to eq(1)
        expect(results.reject(&:success?).map { it.error.resource }).to eq(["feature"])
        expect(Entitlement::SubscriptionFeatureRemoval.where(contract_id: contract.id, entitlement_feature_id: feature.id).count).to eq(1)
        expect(sent_webhooks.map(&:first)).to eq(["contract_entitlement.deleted"])
        expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract_entitlement.deleted", any_args).once
      end
    end
  end
end
