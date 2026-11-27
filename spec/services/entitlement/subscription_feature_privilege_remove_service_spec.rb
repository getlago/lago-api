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

    context "when the plan grants the feature without a value for the privilege" do
      before do
        privilege
        create(:entitlement, feature:, plan:)
      end

      it "still stores a subscription privilege removal" do
        expect { result }.to change(subscription.entitlement_removals.where(privilege:), :count).from(0).to(1)
        expect(result).to be_success
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

    # The organization factory also creates a webhook endpoint.
    let(:organization) { create(:organization, feature_flags:) }
    let(:feature_flags) { %w[entitlement_events] }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
    let(:sso) { create(:privilege, organization:, feature:, code: "sso", value_type: "boolean") }
    let(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
    let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }

    before { privilege }

    # The entitlement of the contract, in the v2 contract entitlement shape.
    def contract_entitlement_render(**fields)
      {lago_contract_id: contract.id, feature_code: "test_feature", **fields}
    end

    def sent_webhooks
      ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { it[:job] == SendWebhookJob }
        .map { ActiveJob::Arguments.deserialize(it[:args]) }
    end

    def removal_rows
      contract.entitlement_removals.reload.map { [it.entitlement_feature_id, it.entitlement_privilege_id] }
    end

    def expect_no_write_and_no_event
      expect(sent_webhooks).to be_empty
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
    end

    context "when the catalog plan sets the value and the contract overrides it" do
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: "20") }

      # max is 20 on the contract over 10 on the plan; sso comes from the plan only.
      let(:before_render) do
        contract_entitlement_render(source: "plan", values: [
          {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
          {privilege_code: "max", value: 20, plan_value: 10, source: "contract"}
        ])
      end
      let(:after_render) do
        contract_entitlement_render(source: "plan", values: [{privilege_code: "sso", value: true, plan_value: true, source: "plan"}])
      end

      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10")
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: "true")
        contract_value
      end

      it "discards the override and its empty row, stores one privilege removal and returns the entitlement after" do
        expect(Entitlement::SubscriptionEntitlement.for_contract(contract).map { V2::ContractEntitlementSerializer.new(it).serialize })
          .to eq([before_render])

        expect(result).to be_success
        expect(result.feature_code).to eq("test_feature")
        expect(result.privilege_code).to eq("max")
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(after_render)
        expect(contract_value.reload).to be_discarded
        expect(contract_entitlement.reload).to be_discarded
        expect(removal_rows).to eq([[nil, privilege.id]])
      end

      it "keeps the value on another contract of the same plan" do
        other_contract = create(:contract, organization:, customer:, catalog_plan:)

        expect(result).to be_success
        expect(Entitlement::SubscriptionEntitlement.for_contract(other_contract).sole.privileges.map(&:code)).to match_array(%w[max sso])
      end

      it "sends one contract_entitlement.updated webhook and activity log with the entitlement after" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob)
          .with("contract_entitlement.updated", contract, {contract_entitlement: after_render})

        expect(sent_webhooks).to eq([["contract_entitlement.updated", contract, {contract_entitlement: after_render}]])
        expect(Utils::ActivityLog).to have_received(:produce).with(
          contract, "contract_entitlement.updated", after_commit: true,
          activity_object: after_render,
          changes: {"values" => [before_render[:values], after_render[:values]]}
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args).once
        expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "subscription.updated", any_args)
        expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "contract.updated", any_args)
      end

      context "when the value is already removed" do
        before { described_class.call(owner: contract, feature_code:, privilege_code:) }

        it "fails with a privilege not found and sends nothing more" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("privilege")
          expect(removal_rows).to eq([[nil, privilege.id]])
          # The first removal only.
          expect(sent_webhooks.size).to eq(1)
          expect(Utils::ActivityLog).to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args).once
        end
      end

      context "when the contract overrides another value of the feature" do
        before { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: sso, value: "false") }

        it "keeps the contract row with that value" do
          expect(result).to be_success
          expect(contract_entitlement.reload).not_to be_discarded
          expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(
            contract_entitlement_render(source: "plan", values: [{privilege_code: "sso", value: false, plan_value: true, source: "contract"}])
          )
        end
      end

      context "without a webhook endpoint" do
        before { organization.webhook_endpoints.destroy_all }

        it "logs the change and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(Utils::ActivityLog).to have_received(:produce).with(
            contract, "contract_entitlement.updated", after_commit: true,
            activity_object: after_render,
            changes: {"values" => [before_render[:values], after_render[:values]]}
          ).once
        end
      end

      context "without the entitlement_events feature flag" do
        let(:feature_flags) { [] }

        it "removes the value, returns the entitlement after and sends nothing" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(after_render)
          expect(contract_value.reload).to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, /\Acontract_entitlement\./, any_args)
        end
      end
    end

    context "when only the catalog plan sets the value" do
      before { create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10") }

      it "stores one privilege removal and writes no contract row" do
        expect(result).to be_success
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(contract_entitlement_render(source: "plan", values: []))
        expect(removal_rows).to eq([[nil, privilege.id]])
        expect(Entitlement::Entitlement.where(contract:)).to be_empty
      end
    end

    context "when the contract sets a value that the catalog plan does not" do
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: "20") }

      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: "true")
        contract_value
      end

      it "discards the value and its empty row, stores no removal and keeps the plan feature" do
        expect(result).to be_success
        expect(contract_value.reload).to be_discarded
        expect(contract_entitlement.reload).to be_discarded
        expect(removal_rows).to be_empty
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(
          contract_entitlement_render(source: "plan", values: [{privilege_code: "sso", value: true, plan_value: true, source: "plan"}])
        )
        expect(sent_webhooks.map(&:first)).to eq(["contract_entitlement.updated"])
      end
    end

    context "when only the contract grants the feature" do
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: "20") }

      before { contract_value }

      it "discards the last value, keeps the row and returns the feature without values" do
        after_render = contract_entitlement_render(source: "contract", values: [])

        expect(result).to be_success
        expect(contract_value.reload).to be_discarded
        expect(contract_entitlement.reload).not_to be_discarded
        expect(removal_rows).to be_empty
        expect(V2::ContractEntitlementSerializer.new(result.entitlement).serialize).to eq(after_render)
        expect(sent_webhooks).to eq([["contract_entitlement.updated", contract, {contract_entitlement: after_render}]])
        expect(Utils::ActivityLog).to have_received(:produce).with(
          contract, "contract_entitlement.updated", after_commit: true,
          activity_object: after_render,
          changes: {"values" => [[{privilege_code: "max", value: 20, plan_value: nil, source: "contract"}], []]}
        ).once
      end
    end

    context "when the feature was never granted to the contract" do
      it "fails with a feature not found, writes nothing and sends nothing" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
        expect(removal_rows).to be_empty
        expect_no_write_and_no_event
      end
    end

    context "when the feature is removed from the contract" do
      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10")
        create(:subscription_feature_removal, :contract, organization:, contract:, feature:)
      end

      it "fails with a feature not found, writes nothing and sends nothing" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("feature")
        expect(removal_rows).to eq([[feature.id, nil]])
        expect_no_write_and_no_event
      end
    end

    context "when neither the plan nor the contract sets the value" do
      before { create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: "true") }

      it "fails with a privilege not found, writes nothing and sends nothing" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
        expect(removal_rows).to be_empty
        expect_no_write_and_no_event
      end
    end

    context "when the plan value is already removed from the contract" do
      let(:removal) { create(:subscription_feature_removal, :contract, organization:, contract:, privilege:) }

      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10")
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: sso, value: "true")
        removal
      end

      it "fails with a privilege not found, writes nothing and sends nothing" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("privilege")
        expect(removal_rows).to eq([[nil, privilege.id]])
        expect(removal.reload).not_to be_discarded
        expect_no_write_and_no_event
      end
    end

    context "with a terminated contract" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }
      let(:contract_value) { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege:, value: "5") }

      before do
        plan_entitlement
        contract_value
      end

      it "refuses the write and sends nothing" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(base: ["contract_not_editable"])
        expect(contract_value.reload).not_to be_discarded
        expect_no_write_and_no_event
      end

      context "with an unknown feature and privilege" do
        let(:feature_code) { "unknown" }
        let(:privilege_code) { "unknown" }

        it "refuses the write as for a known feature" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq(base: ["contract_not_editable"])
        end
      end
    end

    context "when the feature stops applying to the contract during the removal" do
      before do
        plan_entitlement
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10")
        before_read = Entitlement::SubscriptionEntitlement.for_contract_feature(contract, feature)
        # A plan entitlement or feature delete does not lock the contract, so it can commit between the two reads.
        allow(Entitlement::SubscriptionEntitlement).to receive(:for_contract_feature).and_return(before_read, nil)
      end

      it "fails with a feature not found, writes nothing and sends nothing" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("feature")
        expect(contract.entitlement_removals.reload).to be_empty
        expect_no_write_and_no_event
      end
    end

    context "with two concurrent removals of the same value", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      # Committed before the threads start, which only read them.
      before do
        create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege:, value: "10")
        contract
      end

      # Frees the lock holder left waiting by a failed expectation.
      after { release << true }

      it "removes it once, fails the other with a privilege not found and sends one event" do
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
              described_class.call(owner: Contract.find(contract.id), feature_code:, privilege_code:)
            end
          end
        end
        # Both removers wait on the lock, so each one reads the entitlements once it holds the lock.
        expect(removers.map { it.join(0.5) }).to eq([nil, nil])

        release << true
        holder.join
        results = removers.map(&:value)

        expect(results.count(&:success?)).to eq(1)
        expect(results.reject(&:success?).map { it.error.resource }).to eq(["privilege"])
        expect(Entitlement::SubscriptionFeatureRemoval.where(contract_id: contract.id, entitlement_privilege_id: privilege.id).count).to eq(1)
        expect(sent_webhooks.map(&:first)).to eq(["contract_entitlement.updated"])
        expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract_entitlement.updated", any_args).once
      end
    end
  end
end
