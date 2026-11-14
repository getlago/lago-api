# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementQuery do
  before_all do
    create_default(:customer)
  end

  subject do
    described_class.call(
      organization:,
      filters: {
        subscription_id:,
        plan_id:
      }
    )
  end

  let_it_be(:organization) { create_default(:organization) }

  let(:subscription_id) { subscription.id }
  let(:subscription) { create(:subscription, organization:, plan:) }
  let(:seats) { create(:feature, organization:, code: "seats", name: "Nb users") }
  let(:seats_max) { create(:privilege, feature: seats, code: "max", name: "Max", value_type: "integer") }
  let(:seats_reset) { create(:privilege, feature: seats, code: "reset", name: "Password Reset", value_type: "boolean") }
  let(:storage) { create(:feature, organization:, code: "storage", name: "Storage") }
  let(:storage_limit) { create(:privilege, feature: storage, code: "limit", name: "Limit", value_type: "string") }
  let(:storage_type) { create(:privilege, feature: storage, code: "type", name: "Type", value_type: "select", config: {select_options: ["rom", "ram"]}) }
  let(:support) { create(:feature, organization:, code: "support", name: "Premium Support") }
  let(:plan_id) { subscription.plan.parent_id || subscription.plan.id }

  let_it_be(:plan) { create(:plan, organization:) }

  let_it_be(:other_organization_feature) { create(:feature, organization: create(:organization), code: "other") }

  before do
    storage_type
    storage_limit
    seats_reset
    seats_max
    support
    other_organization_feature

    # Other data that should not be retrieved
    other_plan = create(:plan, organization:)
    create_feature_entitlement(other_plan, seats, {seats_max => 555, seats_reset => true})

    other_subscription = create(:subscription, organization:, plan: other_plan)
    create_feature_entitlement(other_subscription, support)
    create_feature_entitlement(other_subscription, seats, {seats_max => 999})
    create_feature_entitlement(other_subscription, storage, {storage_limit => 999_888})
    create(:subscription_feature_removal, subscription: other_subscription, privilege: seats_reset)
  end

  def create_feature_entitlement(parent, feature, privileges = {})
    entitlement = if parent.is_a? Plan
      create(:entitlement, feature:, plan: parent)
    else
      create(:entitlement, feature:, subscription: parent, plan: nil)
    end

    privileges.each do |privilege, value|
      create(:entitlement_value, entitlement:, privilege:, value:)
    end
  end

  def expect_subject_to_match(expected)
    expect(subject.count).to eq expected.count

    result = subject.map(&:to_h).index_by { |h| h[:code] }

    expected.each do |code, feature_expectations|
      privileges_expectations = feature_expectations.delete(:privileges) || {}
      feature_expectations[:code] = code
      expect(result[code]).to include(feature_expectations.stringify_keys)

      expect(result[code][:privileges].count).to eq privileges_expectations.count

      privileges_expectations.each do |expected_privilege|
        expect(result[code][:privileges][expected_privilege[:code]]).to include expected_privilege.stringify_keys
      end
    end
  end

  describe "#call" do
    context "when plan has no features" do
      context "when subscription has no overrides" do
        it "returns empty result" do
          expect(subject).to be_empty
        end
      end

      context "when subscription has feature overrides" do
        it "returns only subscription features" do
          create_feature_entitlement(subscription, seats, {seats_max => 100, seats_reset => true})
          create_feature_entitlement(subscription, storage, {storage_limit => "100GB", storage_type => "ram"})
          create_feature_entitlement(subscription, support)

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100"},
              {code: "reset", value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "limit", value: "100GB"},
              {code: "type", value: "ram"}
            ]},
            "support" => {privileges: []}
          })
        end
      end
    end

    context "when plan has features" do
      before do
        create_feature_entitlement(plan, seats, {seats_max => 20, seats_reset => false})
        create_feature_entitlement(plan, storage, {storage_limit => "50GB", storage_type => "rom"})
        create_feature_entitlement(plan, support)
      end

      context "when subscription has no overrides" do
        it "returns only plans feature" do
          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "20", plan_value: "20", subscription_value: nil},
              {code: "reset", value: "f", plan_value: "f", subscription_value: nil}
            ]},
            "storage" => {privileges: [
              {code: "limit", value: "50GB", plan_value: "50GB", subscription_value: nil},
              {code: "type", value: "rom", plan_value: "rom", subscription_value: nil}
            ]},
            "support" => {privileges: []}
          })
        end
      end

      context "when subscription has privilege value overrides" do
        it "returns all features with overridden values" do
          create_feature_entitlement(subscription, seats, {seats_max => 100, seats_reset => true})
          create_feature_entitlement(subscription, storage, {storage_type => "ram"})

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "limit", value: "50GB", plan_value: "50GB", subscription_value: nil},
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]},
            "support" => {privileges: []}
          })
        end
      end

      context "when a plan feature was removed" do
        it "doesn't return the removed feature" do
          create(:subscription_feature_removal, subscription:, feature: seats)
          create(:subscription_feature_removal, subscription:, feature: support)
          create_feature_entitlement(subscription, storage, {storage_type => "ram"})

          expect_subject_to_match({
            "storage" => {privileges: [
              {code: "limit", value: "50GB", plan_value: "50GB", subscription_value: nil},
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end

      context "when a plan feature privilege was removed" do
        it "doesn't return the removed privilege" do
          create(:subscription_feature_removal, subscription:, privilege: seats_reset)
          create(:subscription_feature_removal, subscription:, privilege: storage_limit)
          create(:subscription_feature_removal, subscription:, feature: support)
          create_feature_entitlement(subscription, storage, {storage_type => "ram"})

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "20", plan_value: "20", subscription_value: nil}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end
    end

    describe "soft deletion" do
      before do
        create_feature_entitlement(plan, seats, {seats_max => 20, seats_reset => false})
        create_feature_entitlement(plan, storage, {storage_limit => "50GB", storage_type => "rom"})
        create_feature_entitlement(plan, support)

        create_feature_entitlement(subscription, seats, {seats_max => 100, seats_reset => true})
        create_feature_entitlement(subscription, storage, {storage_type => "ram"})

        create(:subscription_feature_removal, subscription:, privilege: storage_limit)
        create(:subscription_feature_removal, subscription:, feature: support)
      end

      context "when features are deleted" do
        it "doesn't return the deleted features" do
          seats.discard!

          expect_subject_to_match({
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end

      context "when privileges are deleted" do
        it "doesn't return the deleted features" do
          storage_type.discard!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: []}
          })
        end
      end

      context "when plan entitlement is deleted" do
        it "doesn't return the feature" do
          # NOTE: Notice that we soft delete the entitlement but don't even cleanup the entitlement_values
          Entitlement::Entitlement.where(plan:, feature: seats).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: nil, subscription_value: "100"},
              {code: "reset", value: "t", plan_value: nil, subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end

      context "when subscription entitlement is deleted" do
        it "doesn't return the feature" do
          # NOTE: Notice that we soft delete the entitlement but don't even cleanup the entitlement_values
          #       To retrieve values, the entitlement relation must exist
          Entitlement::Entitlement.where(subscription:, feature: seats).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "20", plan_value: "20", subscription_value: nil},
              {code: "reset", value: "f", plan_value: "f", subscription_value: nil}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end

      context "when plan entitlement value is deleted" do
        it "doesn't return the privilege value from plan" do
          Entitlement::EntitlementValue.where(
            entitlement: Entitlement::Entitlement.where(plan:, feature: storage),
            privilege: storage_type
          ).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: nil, subscription_value: "ram"}
            ]}
          })
        end
      end

      context "when subscription entitlement value is deleted" do
        it "doesn't return the privilege value from subscription" do
          Entitlement::EntitlementValue.where(
            entitlement: Entitlement::Entitlement.where(subscription:, feature: storage),
            privilege: storage_type
          ).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "rom", plan_value: "rom", subscription_value: nil}
            ]}
          })
        end
      end

      context "when plan and subscription entitlement value is deleted" do
        it "doesn't return the privilege" do
          Entitlement::EntitlementValue.where(
            entitlement: Entitlement::Entitlement.where(plan:, feature: storage),
            privilege: storage_type
          ).discard_all!

          Entitlement::EntitlementValue.where(
            entitlement: Entitlement::Entitlement.where(subscription:, feature: storage),
            privilege: storage_type
          ).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: []}
          })
        end
      end

      context "when subscription feature removal is deleted" do
        it "returns the feature" do
          Entitlement::SubscriptionFeatureRemoval.where(subscription:, feature: support).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]},
            "support" => {privileges: []}
          })
        end
      end

      context "when subscription privilege removal is deleted" do
        it "returns the feature" do
          Entitlement::SubscriptionFeatureRemoval.where(subscription:, privilege: storage_limit).discard_all!

          expect_subject_to_match({
            "seats" => {name: "Nb users", privileges: [
              {code: "max", value: "100", plan_value: "20", subscription_value: "100"},
              {code: "reset", value: "t", plan_value: "f", subscription_value: "t"}
            ]},
            "storage" => {privileges: [
              {code: "limit", value: "50GB", plan_value: "50GB", subscription_value: nil},
              {code: "type", value: "ram", plan_value: "rom", subscription_value: "ram"}
            ]}
          })
        end
      end
    end

    context "when the owner is a contract" do
      subject do
        described_class.call(organization:, filters: {contract_id: contract.id, catalog_plan_id: catalog_plan&.id})
      end

      let(:catalog_plan) { create(:catalog_plan, organization:) }
      let(:contract) { create(:contract, organization:, catalog_plan:) }

      def create_owned_entitlement(feature:, values: {}, **owner)
        entitlement = create(:entitlement, feature:, plan: nil, **owner)
        values.each { |privilege, value| create(:entitlement_value, entitlement:, privilege:, value:) }
        entitlement
      end

      # code => [plan_id, subscription_id, {privilege code => [value, plan_value, subscription_value]}]
      def summary
        subject.to_h do |entitlement|
          privileges = entitlement.privileges.to_h { [it.code, [it.value, it.plan_value, it.subscription_value]] }
          [entitlement.code, [entitlement.plan_id, entitlement.subscription_id, privileges]]
        end
      end

      context "when the catalog plan grants a value" do
        before { create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50}) }

        it "returns the catalog plan value without override" do
          expect(summary).to eq("seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil]}])
        end
      end

      context "when the contract overrides a catalog plan value" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50})
          create_owned_entitlement(contract:, feature: seats, values: {seats_max => 60})
        end

        it "returns the contract value as override" do
          expect(summary).to eq("seats" => [catalog_plan.id, contract.id, {"max" => ["60", "50", "60"]}])
        end
      end

      context "when the contract override is deleted" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50})
          create(:entitlement, :contract, contract:, feature: seats, deleted_at: Time.current).tap do |entitlement|
            create(:entitlement_value, entitlement:, privilege: seats_max, value: 60)
          end
        end

        it "returns the catalog plan value" do
          expect(summary).to eq("seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil]}])
        end
      end

      context "when the contract removes a catalog plan feature" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50})
          create_owned_entitlement(catalog_plan:, feature: storage)
          create(:subscription_feature_removal, :contract, contract:, feature: storage)
        end

        it "leaves the removed feature out" do
          expect(summary).to eq("seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil]}])
        end
      end

      context "when the contract removes a catalog plan privilege" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50, seats_reset => "true"})
          create(:subscription_feature_removal, :contract, contract:, privilege: seats_reset)
        end

        it "leaves the removed privilege out" do
          expect(summary).to eq("seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil]}])
        end
      end

      context "when the contract removals are deleted" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50, seats_reset => "true"})
          create_owned_entitlement(catalog_plan:, feature: storage)
          create(:subscription_feature_removal, :contract, contract:, feature: storage, deleted_at: Time.current)
          create(:subscription_feature_removal, :contract, contract:, privilege: seats_reset, deleted_at: Time.current)
        end

        it "returns the feature and the privilege" do
          expect(summary).to eq(
            "seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil], "reset" => ["true", "true", nil]}],
            "storage" => [catalog_plan.id, nil, {}]
          )
        end
      end

      context "when the contract has no catalog plan" do
        let(:catalog_plan) { nil }

        before do
          # A catalog plan row must not match the NULL catalog_plan_id of the contract
          create_owned_entitlement(catalog_plan: create(:catalog_plan, organization:), feature: storage)
        end

        it "returns an empty list" do
          expect(subject).to eq([])
        end

        context "with rows of its own" do
          before { create_owned_entitlement(contract:, feature: seats, values: {seats_max => 60}) }

          it "returns only its own rows" do
            expect(summary).to eq("seats" => [nil, contract.id, {"max" => ["60", nil, "60"]}])
          end
        end
      end

      context "when other owners have rows for the same feature" do
        before do
          create_owned_entitlement(catalog_plan:, feature: seats, values: {seats_max => 50, seats_reset => "true"})

          other_contract = create(:contract, organization:, customer: contract.customer, catalog_plan:)
          create_owned_entitlement(contract: other_contract, feature: seats, values: {seats_max => 70})
          create(:subscription_feature_removal, :contract, contract: other_contract, privilege: seats_reset)

          other_subscription = create(:subscription, organization:, customer: contract.customer)
          create_owned_entitlement(subscription: other_subscription, feature: seats, values: {seats_max => 80})
          create_owned_entitlement(subscription: other_subscription, feature: storage)
          create(:subscription_feature_removal, subscription: other_subscription, feature: seats)
        end

        it "returns only the rows of the contract and its catalog plan" do
          expect(summary).to eq("seats" => [catalog_plan.id, nil, {"max" => ["50", "50", nil], "reset" => ["true", "true", nil]}])
        end
      end
    end

    context "when both a subscription and a contract are given" do
      subject do
        described_class.call(organization:, filters: {subscription_id: SecureRandom.uuid, contract_id: SecureRandom.uuid})
      end

      it "raises an ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, "subscription_id and contract_id are mutually exclusive")
      end
    end

    describe "ordering_date" do
      before do
        seats_plan_ent = Entitlement::Entitlement.create!(created_at: 1.day.ago, organization:, plan:, feature: seats)
        Entitlement::Entitlement.create!(created_at: 9.days.ago, organization:, plan:, feature: support)

        seats_sub_ent = Entitlement::Entitlement.create!(created_at: Time.current, organization:, subscription:, feature: seats)

        Entitlement::EntitlementValue.create!(created_at: 5.days.ago, organization:, entitlement: seats_plan_ent, value: "100", privilege: seats_max)

        Entitlement::EntitlementValue.create!(created_at: 10.days.ago, organization:, entitlement: seats_plan_ent, value: "f", privilege: seats_reset)
        Entitlement::EntitlementValue.create!(created_at: 2.days.ago, organization:, entitlement: seats_sub_ent, value: "t", privilege: seats_reset)
      end

      it "returns the feature ordered by plan entitlement date" do
        expect(subject.map(&:code)).to eq %w[support seats]
        expect(subject.find { it.code == "seats" }.privileges.map(&:code)).to eq %w[reset max]
      end
    end
  end
end
