# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlement, type: :model do
  subject { described_class.first }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:entitlement) { create(:entitlement, feature:, plan: subscription.plan) }
  let(:privilege) { create(:privilege, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, value: "10") }

  before do
    entitlement
    entitlement_value
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature")
      expect(subject).to belong_to(:privilege).class_name("Entitlement::Privilege").optional
    end
  end

  describe "scopes" do
    describe ".for_subscription" do
      let(:subscription) { create(:subscription) }

      it "sets hash-based where conditions correctly" do
        scope = described_class.for_subscription(subscription)

        expect(scope.where_values_hash).to include(
          "organization_id" => subscription.organization_id,
          "removed" => false
        )
        expect(scope.to_sql).to match(/subscription_id = '#{subscription.id}' OR plan_id = '#{subscription.plan.id}'/)
      end

      context "when the plan is an override" do
        let(:subscription) do
          create(:subscription, organization:, plan: create(:plan, organization:, parent: create(:plan, organization:)))
        end

        it "sets hash-based where conditions correctly" do
          scope = described_class.for_subscription(subscription)

          expect(scope.where_values_hash).to include(
            "organization_id" => subscription.organization_id,
            "removed" => false
          )
          expect(scope.to_sql).to match(/subscription_id = '#{subscription.id}' OR plan_id = '#{subscription.plan.parent_id}'/)
        end
      end
    end
  end

  describe "#readonly?" do
    it do
      expect(subject).to be_readonly
    end
  end

  it do
    expect(subject.attributes).to eq({
      "entitlement_feature_id" => feature.id,
      "organization_id" => organization.id,
      "feature_code" => feature.code,
      "feature_name" => feature.name,
      "feature_description" => feature.description,
      "feature_deleted_at" => nil,
      "entitlement_privilege_id" => privilege.id,
      "privilege_code" => privilege.code,
      "privilege_name" => nil,
      "privilege_value_type" => "string",
      "privilege_config" => {},
      "privilege_deleted_at" => nil,
      "plan_id" => entitlement.plan_id,
      "subscription_id" => nil,
      "removed" => false,
      "plan_entitlement_id" => entitlement.id,
      "override_entitlement_id" => nil,
      "plan_entitlement_values_id" => entitlement_value.id,
      "override_entitlement_values_id" => nil,
      "privilege_plan_value" => "10",
      "privilege_override_value" => nil
    })
  end
end
