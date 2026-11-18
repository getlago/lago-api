# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementCoreUpdateService do
  before_all do
    create_default(:customer)
  end

  subject(:result) { described_class.call(owner: subscription, plan:, feature: seats, plan_entitlement:, sub_entitlement:, privilege_params:, partial:) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:subscription) { create(:subscription, organization:, plan:) }

  let(:plan_entitlement) { plan.entitlements.includes(values: :privilege).find_by(feature: seats) }
  let(:sub_entitlement) { subscription.entitlements.includes(values: :privilege).find_by(feature: seats) }

  let(:seats) { create(:feature, organization:, code: "seats", name: "Nb users") }
  let(:seats_max) { create(:privilege, feature: seats, code: "max", name: "Max", value_type: "integer") }
  let(:seats_reset) { create(:privilege, feature: seats, code: "reset", name: "Password Reset", value_type: "boolean") }
  let(:seats_signin) { create(:privilege, feature: seats, code: "signin", name: "Sign In", value_type: "select", config: {select_options: ["password", "okta"]}) }

  let_it_be(:same_code_feature) { create(:feature, organization: create(:organization), code: "seats", name: "Nb users") }

  before do
    seats_reset
    seats_max
    same_code_feature
  end

  def expect_entitlement_to_match(privilege_params)
    ent = Entitlement::SubscriptionEntitlement.for_subscription(subscription).find { it.code == "seats" }
    ent_values = ent.privileges.map do |priv|
      [priv.code, Utils::Entitlement.cast_value(priv.value, priv.value_type)]
    end.to_h
    expect(ent_values).to eq privilege_params
  end

  # The core service takes no lock: it relies on the subscription lock that its two callers,
  # SubscriptionEntitlementsUpdateService and SubscriptionEntitlementUpdateService, take before they read
  # plan_entitlement and sub_entitlement. Their specs cover the concurrent writes.
  describe "#call" do
    context "when plan has no feature" do
      context "when subscription has no feature" do
        let(:privilege_params) { {seats_max.code => 100, seats_reset.code => true} }

        context "when partial" do
          let(:partial) { true }

          it "adds the feature to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            sub_ent = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_ent.feature).to eq seats
            expect(sub_ent.values.count).to eq 2
            expect(sub_ent.values.map { it.privilege.code }).to match_array privilege_params.keys
          end
        end

        context "when full" do
          let(:partial) { false }

          it "adds the feature to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            sub_ent = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_ent.feature).to eq seats
            expect(sub_ent.values.count).to eq 2
            expect(sub_ent.values.map { it.privilege.code }).to match_array privilege_params.keys
          end
        end
      end

      context "when subscription already has feature" do
        let(:privilege_params) { {seats_max.code => 100, seats_reset.code => true} }
        let(:sub_entitlement) { create(:entitlement, subscription:, plan: nil, feature: seats) }
        let(:max_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_max, value: 2) }
        let(:reset_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_reset, value: false) }
        let(:signin_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_signin, value: "okta") }

        before do
          max_value
          reset_value
          signin_value
        end

        context "when partial" do
          let(:partial) { true }

          it "updates the existing values" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params.merge(seats_signin.code => "okta"))
            expect(subscription.entitlements.count).to eq 1
            expect(max_value.reload.value).to eq "100"
            expect(reset_value.reload.value).to eq "true"
            expect(signin_value.reload.value).to eq "okta"
            expect(signin_value).not_to be_discarded
          end
        end

        context "when full" do
          let(:partial) { false }

          it "adds the feature to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            expect(subscription.entitlements.count).to eq 1
            expect(max_value.reload.value).to eq "100"
            expect(reset_value.reload.value).to eq "true"
            expect(signin_value.reload).to be_discarded
          end
        end
      end
    end

    context "when plan has the feature" do
      let(:privilege_params) { {seats_max.code => 100, seats_reset.code => true} }

      let(:plan_entitlement) { create(:entitlement, plan:, feature: seats) }
      let(:max_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege: seats_max, value: 2) }
      let(:reset_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege: seats_reset, value: false) }
      let(:signin_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege: seats_signin, value: "okta") }

      # Create discarded feature and privilege removal
      let(:discarded_seats_removal) { create(:subscription_feature_removal, feature: seats, subscription:, deleted_at: 1.day.ago) }
      let(:discarded_max_removal) { create(:subscription_feature_removal, privilege: seats_max, subscription:, deleted_at: 1.day.ago) }
      let(:discarded_reset_removal) { create(:subscription_feature_removal, privilege: seats_reset, subscription:, deleted_at: 1.day.ago) }
      let(:discarded_signin_removal) { create(:subscription_feature_removal, privilege: seats_signin, subscription:, deleted_at: 1.day.ago) }

      before do
        max_value
        reset_value
        signin_value
        discarded_seats_removal
        discarded_max_removal
        discarded_reset_removal
        discarded_signin_removal
      end

      context "when privilege_params match plan values in a different order" do
        let(:privilege_params) { {seats_signin.code => "okta", seats_reset.code => false, seats_max.code => 2} }

        context "when subscription has no overrides" do
          let(:partial) { false }

          it "removes subscription overrides and restores plan defaults" do
            expect(result).to be_success
            expect(subscription.entitlements.count).to eq 0
          end
        end

        context "when subscription already has overrides" do
          let(:partial) { false }
          let(:sub_entitlement) { create(:entitlement, feature: seats, subscription:, plan: nil) }
          let(:sub_max_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_max, value: 50, updated_at: 1.day.ago) }

          before { sub_max_value }

          it "discards subscription entitlement and restores plan defaults" do
            expect(result).to be_success
            expect(sub_entitlement.reload).to be_discarded
            expect(sub_max_value.reload).to be_discarded
          end

          it "sets updated_at on the discarded values" do
            freeze_time do
              result

              expect(sub_max_value.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
            end
          end
        end
      end

      context "when subscription has no entitlements" do
        context "when partial" do
          let(:partial) { true }

          it "adds overrides to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params.merge(seats_signin.code => "okta"))
            sub_ent = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_ent.values.map(&:value)).to contain_exactly("100", "true")
            expect(sub_ent.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code)
          end
        end

        context "when full" do
          let(:partial) { false }

          it "adds overrides to the subscription and create a privilege removal" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            sub_ent = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_ent.values.map(&:value)).to contain_exactly("100", "true")
            expect(sub_ent.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code)

            expect(subscription.entitlement_removals.count).to eq 1
            expect(subscription.entitlement_removals.where(privilege: seats_signin)).to exist
          end
        end

        context "when the feature is removed from the subscription" do
          let(:partial) { true }
          let(:seats_removal) { create(:subscription_feature_removal, feature: seats, subscription:, updated_at: 1.day.ago) }

          before { seats_removal }

          it "discards the feature removal and sets its updated_at" do
            freeze_time do
              result

              expect(seats_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
            end
          end
        end
      end

      context "when subscription already has overrides" do
        let(:sub_entitlement) { create(:entitlement, feature: seats, subscription:, plan: nil) }
        let(:sub_max_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_max, value: 50) }
        let(:sub_signin_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege: seats_signin, value: "password") }

        before do
          sub_max_value
          sub_signin_value
        end

        context "when partial" do
          let(:partial) { true }

          it "adds overrides to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params.merge(seats_signin.code => "password"))
            expect(subscription.entitlements.count).to eq 1
            expect(sub_max_value.reload.value).to eq "100"
            expect(sub_entitlement.values.map(&:value)).to contain_exactly("100", "true", "password")
            expect(sub_entitlement.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code, seats_signin.code)
          end
        end

        context "when full" do
          let(:partial) { false }

          it "adds overrides to the subscription and create a privilege removal" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            sub_ent = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_ent.values.map(&:value)).to contain_exactly("100", "true")
            expect(sub_ent.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code)

            expect(subscription.entitlement_removals.count).to eq 1
            expect(subscription.entitlement_removals.where(privilege: seats_signin)).to exist
            expect(sub_signin_value.reload).to be_discarded
          end
        end
      end

      context "when re-adding a removed privilege at the plan default value" do
        let(:privilege_params) { {seats_max.code => 2} }
        let(:max_removal) { create(:subscription_feature_removal, privilege: seats_max, subscription:, updated_at: 1.day.ago) }

        before { max_removal }

        context "when partial" do
          let(:partial) { true }

          it "sets updated_at on the discarded privilege removal" do
            freeze_time do
              result

              expect(max_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
            end
          end

          it "discards the privilege removal so the plan default is restored" do
            expect(result).to be_success
            expect(max_removal.reload).to be_discarded
            expect(subscription.entitlement_removals.where(privilege: seats_max)).not_to exist

            ent = Entitlement::SubscriptionEntitlement.for_subscription(subscription).find { it.code == "seats" }
            max_priv = ent.privileges.find { it.code == seats_max.code }
            expect(Utils::Entitlement.cast_value(max_priv.value, max_priv.value_type)).to eq 2
          end
        end
      end

      context "when subscription has privilege removals" do
        let(:max_removal) { create(:subscription_feature_removal, privilege: seats_max, subscription:) }
        let(:reset_removal) { create(:subscription_feature_removal, privilege: seats_reset, subscription:) }
        let(:signin_removal) { create(:subscription_feature_removal, privilege: seats_signin, subscription:) }

        before do
          max_removal
          reset_removal
          signin_removal
        end

        context "when partial" do
          let(:partial) { true }

          it "adds overrides to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            expect(subscription.entitlements.count).to eq 1

            sub_entitlement = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_entitlement.values.map(&:value)).to contain_exactly("100", "true")
            expect(sub_entitlement.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code)

            expect(max_removal.reload).to be_discarded
            expect(reset_removal.reload).to be_discarded

            # QUESTION: Feature is not in plan, should this be cleaned up?
            expect(signin_removal.reload).not_to be_discarded
          end
        end

        context "when full" do
          let(:partial) { false }

          it "adds overrides to the subscription" do
            expect(result).to be_success
            expect_entitlement_to_match(privilege_params)
            expect(subscription.entitlements.count).to eq 1

            sub_entitlement = subscription.entitlements.includes(values: :privilege).sole
            expect(sub_entitlement.values.map(&:value)).to contain_exactly("100", "true")
            expect(sub_entitlement.values.map { it.privilege.code }).to contain_exactly(seats_max.code, seats_reset.code)

            expect(max_removal.reload).to be_discarded
            expect(reset_removal.reload).to be_discarded

            # QUESTION: Feature is not in plan, should this be cleaned up?
            expect(signin_removal.reload).not_to be_discarded
          end
        end
      end
    end
  end

  describe "#call with a contract owner" do
    subject(:result) do
      described_class.call(
        owner: contract,
        plan: catalog_plan,
        feature: seats,
        plan_entitlement: contract_plan_entitlement,
        sub_entitlement: contract_entitlement,
        privilege_params:,
        partial: true,
        path:
      )
    end

    let(:path) { nil }
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:contract) { create(:contract, organization:, catalog_plan:) }
    let(:catalog_plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: seats) }
    let(:contract_plan_entitlement) { catalog_plan.entitlements.includes(values: :privilege).find_by(feature: seats) }
    let(:contract_entitlement) { contract.entitlements.includes(values: :privilege).find_by(feature: seats) }

    def contract_values
      Entitlement::SubscriptionEntitlement.for_contract(contract).find { it.code == "seats" }
        &.privileges&.to_h { [it.code, Utils::Entitlement.cast_value(it.value, it.value_type)] }
    end

    context "when the catalog plan grants the feature" do
      before { create(:entitlement_value, entitlement: catalog_plan_entitlement, privilege: seats_max, value: 10) }

      context "with another value" do
        let(:privilege_params) { {seats_max.code => 60} }

        it "stores an override on the contract" do
          expect(result).to be_success
          expect(contract_values).to eq("max" => 60)
          expect(contract.entitlements.sole.values.sole.value).to eq("60")
          expect(subscription.entitlements).to be_empty
        end
      end

      context "with the value of the catalog plan" do
        let(:privilege_params) { {seats_max.code => 10} }

        let(:override) { create(:entitlement, :contract, organization:, contract:, feature: seats, created_at: 1.day.ago, updated_at: 1.day.ago) }
        let(:override_value) { create(:entitlement_value, entitlement: override, privilege: seats_max, value: 60, updated_at: 1.day.ago) }
        let(:removal) do
          create(:subscription_feature_removal, :contract, organization:, contract:, privilege: seats_reset, updated_at: 1.day.ago)
        end

        before do
          override_value
          override.update_column(:updated_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
          removal
        end

        it "drops the override and the removals of the contract" do
          expect(result).to be_success
          expect(contract.entitlements.reload).to be_empty
          expect(contract.entitlement_removals.reload).to be_empty
          expect(contract_values).to eq("max" => 10)
        end

        it "sets updated_at on the rows it discards" do
          freeze_time do
            result

            expect(Entitlement::EntitlementValue.with_discarded.find(override_value.id).updated_at).to eq(Time.current)
            expect(Entitlement::SubscriptionFeatureRemoval.with_discarded.find(removal.id).updated_at).to eq(Time.current)
          end
        end
      end
    end

    context "when only the contract grants the feature" do
      let(:privilege_params) { {seats_max.code => 60, seats_reset.code => true} }

      it "adds the feature to the contract" do
        expect(result).to be_success
        expect(contract.entitlements.sole.feature).to eq(seats)
        expect(contract_values).to eq("max" => 60, "reset" => true)
      end
    end

    context "with the path of the entry" do
      let(:path) { :"entitlements.seats" }

      before { create(:entitlement_value, entitlement: catalog_plan_entitlement, privilege: seats_max, value: 10) }

      context "with an unknown privilege" do
        let(:privilege_params) { {seats_max.code => 60, "unknown" => 1} }

        it "fails on the path of the privilege before any write" do
          expect { result }.to raise_error(BaseService::NotFoundFailure) do |error|
            expect(error.error_code).to eq("privilege_not_found")
            expect(error.result.failed_field).to eq(:"entitlements.seats.unknown")
          end
          expect(contract.entitlements.reload).to be_empty
        end
      end

      context "with a value of the wrong type equal to the catalog plan value once cast" do
        let(:privilege_params) { {seats_max.code => "10.0"} }

        it "fails on the path of the privilege" do
          expect { result }.to raise_error(BaseService::ValidationFailure) do |error|
            expect(error.messages).to eq(max_privilege_value: ["value_is_invalid"])
            expect(error.codes).to eq("entitlements.seats.max": ["value_is_invalid"])
          end
        end
      end

      context "with a value that the entitlement value refuses" do
        let(:privilege_params) { {seats_max.code => nil} }

        it "fails on the path of the privilege with the keys of v1" do
          expect { result }.to raise_error(BaseService::ValidationFailure) do |error|
            expect(error.messages).to eq("privilege.value": ["value_is_mandatory"])
            expect(error.codes).to eq("entitlements.seats.max": ["value_is_mandatory"])
          end
          expect(contract.entitlements.reload).to be_empty
        end
      end
    end
  end
end
