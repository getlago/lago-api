# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::ContractEntitlementUpdateService do
  subject(:result) { described_class.call(contract:, entitlements_params:) }

  let_it_be(:organization, refind: true) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let_it_be(:seats) { create(:feature, organization:, code: "seats") }
  let_it_be(:seats_max) { create(:privilege, organization:, feature: seats, code: "max", value_type: "integer") }
  let_it_be(:seats_sso) { create(:privilege, organization:, feature: seats, code: "sso", value_type: "boolean") }
  let_it_be(:seats_tier) do
    create(:privilege, organization:, feature: seats, code: "tier", value_type: "select", config: {select_options: %w[gold silver]})
  end
  let_it_be(:storage) { create(:feature, organization:, code: "storage") }
  let_it_be(:storage_limit) { create(:privilege, organization:, feature: storage, code: "limit", value_type: "integer") }
  let_it_be(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: seats) }

  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
  let(:entitlements_params) { {"seats" => {"max" => 60}} }

  before_all do
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: seats_max, value: "50")
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: seats_sso, value: "true")
  end

  # The effective values of a feature, as the contract read renders them.
  def effective_values(code)
    entitlement = Entitlement::SubscriptionEntitlement.for_contract(contract).find { it.code == code }
    entitlement&.privileges&.to_h { [it.code, Utils::Entitlement.cast_value(it.value, it.value_type)] }
  end

  describe "#call" do
    it "stores the value as an override of the catalog plan" do
      expect(result).to be_success

      contract_entitlement = contract.entitlements.sole
      expect(contract_entitlement.feature).to eq(seats)
      expect(contract_entitlement.values.map { [it.privilege.code, it.value] }).to eq([["max", "60"]])
      expect(effective_values("seats")).to eq("max" => 60, "sso" => true)
      expect(plan_entitlement.values.reload.map(&:value)).to contain_exactly("50", "true")
    end

    it "returns every entitlement of the contract" do
      max = result.entitlements.sole.privileges.find { it.code == "max" }

      expect(result.entitlements.map { [it.contract, it.code] }).to eq([[contract, "seats"]])
      expect([max.plan_value, max.subscription_value]).to eq(%w[50 60])
    end

    it "logs nothing without the entitlement_events feature flag" do
      result

      expect(Utils::ActivityLog).not_to have_received(:produce)
    end

    context "with the entitlement_events feature flag" do
      before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

      it "logs the changed entitlement under the contract, with its values before and after" do
        result

        values_before = [
          {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
          {privilege_code: "max", value: 50, plan_value: 50, source: "plan"}
        ]
        values_after = [
          {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
          {privilege_code: "max", value: 60, plan_value: 50, source: "contract"}
        ]
        expect(Utils::ActivityLog).to have_received(:produce).with(
          contract, "contract_entitlement.updated", after_commit: true,
          activity_object: {
            lago_contract_id: contract.id,
            feature_code: "seats",
            source: "plan",
            values: values_after
          },
          changes: {"values" => [values_before, values_after]}
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).once
      end

      it "locks the catalog plan so that its writes wait for the logs" do
        allow(Utils::ActivityLog).to receive(:available?).and_return(true)
        allow(Utils::KafkaProducer).to receive(:produce_async)
        queries = []
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { queries << it.payload[:sql] }

        result

        ActiveSupport::Notifications.unsubscribe(subscriber)
        expect(queries).to include(a_string_matching(/FROM "catalog_plans".*FOR SHARE/m))
      end

      context "when activity logs cannot be sent" do
        before { allow(Utils::ActivityLog).to receive(:available?).and_return(false) }

        it "logs nothing and reads the contract entitlements once" do
          allow(Entitlement::SubscriptionEntitlement).to receive(:for_contract).and_call_original

          expect(result).to be_success
          expect(Utils::ActivityLog).not_to have_received(:produce)
          expect(Entitlement::SubscriptionEntitlement).to have_received(:for_contract).once
        end
      end

      context "when the same write runs again" do
        before { described_class.call(contract:, entitlements_params:) }

        it "logs nothing" do
          expect { result }.not_to change(Entitlement::EntitlementValue, :count)

          expect(Utils::ActivityLog).to have_received(:produce).once
        end
      end

      context "with several changed features" do
        let(:entitlements_params) { {"seats" => {"max" => 60}, "storage" => {"limit" => 10}} }

        it "logs each one, newest first as the contract read lists them" do
          result

          expect(Utils::ActivityLog).to have_received(:produce)
            .with(contract, "contract_entitlement.created", hash_including(activity_object: hash_including(feature_code: "storage")))
            .ordered
          expect(Utils::ActivityLog).to have_received(:produce)
            .with(contract, "contract_entitlement.updated", hash_including(activity_object: hash_including(feature_code: "seats")))
            .ordered
          expect(Utils::ActivityLog).to have_received(:produce).twice
        end
      end

      context "with an empty body" do
        let(:entitlements_params) { {} }

        it "reads the contract entitlements once and logs nothing" do
          allow(Entitlement::SubscriptionEntitlement).to receive(:for_contract).and_call_original

          expect(result).to be_success
          expect(Entitlement::SubscriptionEntitlement).to have_received(:for_contract).once
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      context "when the write fails after the logs are built" do
        before do
          allow(Utils::ActivityLog).to receive(:available?).and_return(true)
          allow(Utils::KafkaProducer).to receive(:produce_async)
          allow(Utils::ActivityLog).to receive(:produce_after_commit).and_wrap_original do |original, *args, **kwargs|
            original.call(*args, **kwargs)
            raise ActiveRecord::RecordInvalid, contract
          end
        end

        it "rolls back and sends no log" do
          expect(result).not_to be_success
          expect(contract.entitlements.reload).to be_empty
          expect(Utils::ActivityLog).to have_received(:produce).once
          expect(Utils::KafkaProducer).not_to have_received(:produce_async)
        end
      end
    end

    it "sends no webhook" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
    end

    context "with an existing override" do
      let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature: seats) }

      before { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: seats_max, value: "70") }

      it "updates it and keeps the other values" do
        expect(result).to be_success

        expect(contract_entitlement.values.reload.map(&:value)).to eq(["60"])
        expect(effective_values("seats")).to eq("max" => 60, "sso" => true)
      end

      context "when the value equals the catalog plan value" do
        let(:entitlements_params) { {"seats" => {"max" => 50}} }

        it "drops the override and leaves no empty contract entitlement" do
          expect(result).to be_success

          expect(contract_entitlement.values.reload).to be_empty
          expect(contract.entitlements.reload).to be_empty
          expect(effective_values("seats")).to eq("max" => 50, "sso" => true)
        end

        context "with the entitlement_events feature flag" do
          before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

          it "logs it as updated, back to the catalog plan value" do
            result

            values_before = [
              {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
              {privilege_code: "max", value: 70, plan_value: 50, source: "contract"}
            ]
            values_after = [
              {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
              {privilege_code: "max", value: 50, plan_value: 50, source: "plan"}
            ]
            expect(Utils::ActivityLog).to have_received(:produce).with(
              contract, "contract_entitlement.updated", after_commit: true,
              activity_object: hash_including(feature_code: "seats", values: values_after),
              changes: {"values" => [values_before, values_after]}
            ).once
          end
        end

        context "when the override has another value" do
          before { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: seats_sso, value: "false") }

          it "keeps the contract entitlement with that value" do
            expect(result).to be_success

            expect(contract.entitlements.reload).to eq([contract_entitlement])
            expect(contract_entitlement.values.reload.map(&:value)).to eq(["false"])
            expect(effective_values("seats")).to eq("max" => 50, "sso" => false)
          end
        end
      end

      context "when every value equals the catalog plan values" do
        let(:entitlements_params) { {"seats" => {"max" => 50, "sso" => true}} }

        it "drops the contract entitlement" do
          expect(result).to be_success

          expect(contract.entitlements.reload).to be_empty
          expect(effective_values("seats")).to eq("max" => 50, "sso" => true)
        end

        context "when the override also sets a privilege that the body does not name" do
          before { create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: seats_tier, value: "gold") }

          it "keeps that override and drops the others" do
            expect(result).to be_success

            expect(contract.entitlements.reload).to eq([contract_entitlement])
            expect(contract_entitlement.values.reload.map { [it.privilege.code, it.value] }).to eq([["tier", "gold"]])
            expect(effective_values("seats")).to eq("max" => 50, "sso" => true, "tier" => "gold")
          end
        end
      end
    end

    context "when the value equals the catalog plan value without an override" do
      let(:entitlements_params) { {"seats" => {"max" => 50}} }

      it "stores nothing" do
        expect(result).to be_success

        expect(contract.entitlements.reload).to be_empty
        expect(effective_values("seats")).to eq("max" => 50, "sso" => true)
      end

      context "with the entitlement_events feature flag" do
        before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

        it "logs nothing" do
          expect(result).to be_success
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end
    end

    context "with an empty privilege map for a feature of the catalog plan" do
      let(:entitlements_params) { {"seats" => {}} }

      it "stores nothing" do
        expect(result).to be_success

        expect(contract.entitlements.reload).to be_empty
        expect(effective_values("seats")).to eq("max" => 50, "sso" => true)
      end
    end

    context "with an empty privilege map for a feature that only the contract grants" do
      let(:entitlements_params) { {"storage" => {}} }

      it "grants the feature without values" do
        expect(result).to be_success

        expect(contract.entitlements.sole.feature).to eq(storage)
        expect(effective_values("storage")).to eq({})
      end
    end

    context "with a feature that only the contract grants" do
      let(:entitlements_params) { {"storage" => {"limit" => 10}} }

      it "adds it to the contract" do
        expect(result).to be_success

        expect(contract.entitlements.sole.feature).to eq(storage)
        expect(effective_values("storage")).to eq("limit" => 10)
        expect(result.entitlements.map(&:code)).to eq(%w[storage seats])
      end

      context "with the entitlement_events feature flag" do
        before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

        it "logs it as created" do
          result

          values = [{privilege_code: "limit", value: 10, plan_value: nil, source: "contract"}]
          expect(Utils::ActivityLog).to have_received(:produce).with(
            contract, "contract_entitlement.created", after_commit: true,
            activity_object: hash_including(feature_code: "storage", source: "contract", values:),
            changes: {"values" => [nil, values]}
          ).once
        end
      end
    end

    context "with a feature removed from the contract" do
      before { create(:subscription_feature_removal, :contract, organization:, contract:, feature: seats) }

      it "grants it back with the new value" do
        expect(result).to be_success

        expect(contract.entitlement_removals.reload).to be_empty
        expect(effective_values("seats")).to eq("max" => 60, "sso" => true)
      end

      context "with the entitlement_events feature flag" do
        before { organization.update!(feature_flags: organization.feature_flags | ["entitlement_events"]) }

        # The removed feature was not in the contract read, so granting it back creates it there, from the plan.
        it "logs it as created" do
          result

          values = [
            {privilege_code: "sso", value: true, plan_value: true, source: "plan"},
            {privilege_code: "max", value: 60, plan_value: 50, source: "contract"}
          ]
          expect(Utils::ActivityLog).to have_received(:produce).with(
            contract, "contract_entitlement.created", after_commit: true,
            activity_object: hash_including(feature_code: "seats", source: "plan", values:),
            changes: {"values" => [nil, values]}
          ).once
        end
      end
    end

    context "with a contract without a catalog plan" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan: nil) }

      it "adds the feature to the contract" do
        expect(result).to be_success

        expect(effective_values("seats")).to eq("max" => 60)
      end
    end

    context "with a pending contract" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

      it "stores the override" do
        expect(result).to be_success
        expect(effective_values("seats")).to eq("max" => 60, "sso" => true)
      end
    end

    %i[terminated canceled].each do |status|
      context "with a #{status} contract" do
        let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }

        it "refuses the write" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(base: ["contract_not_editable"])
          expect(result.failed_field).to be_nil
          expect(contract.entitlements.reload).to be_empty
        end
      end
    end

    context "when the contract is terminated after it was loaded" do
      before do
        contract
        Contract.where(id: contract.id).update_all(status: "terminated", terminated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      it "refuses the write on the status read under the lock" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(base: ["contract_not_editable"])
        expect(Entitlement::Entitlement.where(contract_id: contract.id)).to be_empty
      end
    end

    context "without a contract" do
      let(:contract) { nil }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("contract_not_found")
      end
    end

    context "with an unknown feature" do
      let(:entitlements_params) { {"storage" => {"limit" => 10}, "unknown" => {"max" => 1}} }

      it "fails on the entry and rolls back" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
        expect(result.failed_field).to eq(:"entitlements.unknown")
        expect(contract.entitlements.reload).to be_empty
      end
    end

    context "with a null feature value" do
      let(:entitlements_params) { {"storage" => {"limit" => 10}, "seats" => nil} }

      it "fails on the feature entry and rolls back" do
        expect(result).not_to be_success
        expect(result.error.codes).to eq("entitlements.seats": ["value_is_invalid"])
        expect(result.failed_field).to be_nil
        expect(contract.entitlements.reload).to be_empty
      end
    end

    ["", false, []].each do |blank_value|
      context "with a blank feature value (#{blank_value.inspect})" do
        let(:entitlements_params) { {"storage" => {"limit" => 10}, "seats" => blank_value} }

        it "fails on the feature entry and rolls back" do
          expect(result).not_to be_success
          expect(result.error.codes).to eq("entitlements.seats": ["value_is_invalid"])
          expect(contract.entitlements.reload).to be_empty
        end
      end
    end

    context "with an unknown feature whose value is null" do
      let(:entitlements_params) { {"unknown" => nil} }

      it "fails on the unknown feature" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
        expect(result.failed_field).to eq(:"entitlements.unknown")
      end
    end

    context "with an unknown feature whose value is not a map" do
      let(:entitlements_params) { {"unknown" => [1]} }

      it "fails on the unknown feature" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
        expect(result.failed_field).to eq(:"entitlements.unknown")
      end
    end

    context "with an unknown privilege" do
      let(:entitlements_params) { {"seats" => {"max" => 60, "unknown" => 1}} }

      it "fails on the entry" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
        expect(result.failed_field).to eq(:"entitlements.seats.unknown")
        expect(contract.entitlements.reload).to be_empty
      end
    end

    context "with an invalid value" do
      let(:entitlements_params) { {"seats" => {"max" => "many"}} }

      it "fails on the path of the entry" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(max_privilege_value: ["value_is_invalid"])
        expect(result.error.codes).to eq("entitlements.seats.max": ["value_is_invalid"])
        expect(result.failed_field).to be_nil
      end
    end

    context "with a feature value that is not a map" do
      let(:entitlements_params) { {"seats" => [60]} }

      it "fails on the feature entry" do
        expect(result).not_to be_success
        expect(result.error.codes).to eq("entitlements.seats": ["value_is_invalid"])
        expect(result.failed_field).to be_nil
        expect(contract.entitlements.reload).to be_empty
      end
    end

    context "with a privilege value that is not a scalar" do
      let(:entitlements_params) { {"seats" => {"max" => [60]}} }

      it "fails on the privilege entry before comparing it with the plan value" do
        expect(result).not_to be_success
        expect(result.error.codes).to eq("entitlements.seats.max": ["value_is_invalid"])
        expect(result.failed_field).to be_nil
        expect(contract.entitlements.reload).to be_empty
      end
    end

    context "with a value outside the select options" do
      let(:entitlements_params) { {"seats" => {"tier" => "bronze"}} }

      it "fails with the allowed values" do
        expect(result).not_to be_success
        expect(result.error.codes).to eq("entitlements.seats.tier": ["value_not_in_select_options"])
        expect(result.error.meta).to eq("entitlements.seats.tier": {allowed_values: %w[gold silver]})
      end
    end

    context "with a null value" do
      let(:entitlements_params) { {"seats" => {"max" => nil}} }

      it "fails on the path of the entry" do
        expect(result).not_to be_success
        expect(result.error.codes).to eq("entitlements.seats.max": ["value_is_mandatory"])
        expect(result.failed_field).to be_nil
      end
    end

    context "when a concurrent request creates the same entitlement" do
      before do
        # The concurrent request inserts its row after this one read the contract entitlements.
        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken feature" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(feature: ["value_already_exist"])
        expect(contract.entitlements.reload).to be_empty
      end
    end
  end
end
