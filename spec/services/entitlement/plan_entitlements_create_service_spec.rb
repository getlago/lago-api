# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementsCreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, plan:, entitlements_params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:entitlements_params) do
    {
      "seats" => {
        "max" => 25
      }
    }
  end

  before do
    feature
    privilege
  end

  describe "#call" do
    subject(:result) { create_service.call }

    it "returns success" do
      expect(result).to be_success
    end

    it "creates entitlements for the plan" do
      expect { result }.to change { plan.entitlements.count }.by(1)
    end

    it "creates entitlement values" do
      expect { result }.to change(Entitlement::EntitlementValue, :count).by(1)
    end

    it "returns the entitlements in the result" do
      expect(result.entitlements).to be_present
      expect(result.entitlements.count).to eq(1)
    end

    it "creates the entitlement with correct values" do
      result
      entitlement = plan.entitlements.first
      entitlement_value = entitlement.values.first

      expect(entitlement.feature).to eq(feature)
      expect(entitlement_value.privilege).to eq(privilege)
      expect(entitlement_value.value).to eq("25")
    end

    context "when plan has existing entitlements" do
      let(:existing_entitlement) { create(:entitlement, organization:, plan:, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      before do
        existing_entitlement
        existing_value
      end

      it "deletes existing entitlements and their values" do
        expect { result }.to change(Entitlement::Entitlement, :count).by(0)
          .and change(Entitlement::EntitlementValue, :count).by(0)
      end

      it "creates new entitlements" do
        result
        new_entitlement = plan.entitlements.first
        new_value = new_entitlement.values.first

        expect(new_entitlement).not_to eq(existing_entitlement)
        expect(new_value.value).to eq("25")
      end
    end

    context "when entitlements_params is empty" do
      let(:entitlements_params) { {} }

      it "returns success" do
        expect(result).to be_success
      end

      it "does not create any entitlements" do
        expect { result }.not_to change { plan.entitlements.count }
      end
    end

    context "when feature has multiple privileges" do
      let(:privilege2) { create(:privilege, organization:, feature:, code: "max_admins", value_type: "integer") }
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => 25,
            "max_admins" => 5
          }
        }
      end

      before do
        privilege2
      end

      it "creates entitlement values for all privileges" do
        expect { result }.to change(Entitlement::EntitlementValue, :count).by(2)
      end

      it "creates correct values for each privilege" do
        result
        entitlement = plan.entitlements.first
        values = entitlement.values.index_by(&:privilege)

        expect(values[privilege].value).to eq("25")
        expect(values[privilege2].value).to eq("5")
      end
    end

    context "when feature does not exist" do
      let(:entitlements_params) do
        {
          "nonexistent_feature" => {
            "max" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
      end
    end

    context "when privilege does not exist" do
      let(:entitlements_params) do
        {
          "seats" => {
            "nonexistent_privilege" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end

    context "when plan is nil" do
      subject(:create_service) { described_class.new(organization:, plan: nil, entitlements_params:) }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "when feature has no privileges in payload" do
      let(:entitlements_params) do
        {
          "seats" => {}
        }
      end

      it "creates entitlement without values" do
        expect { result }.to change { plan.entitlements.count }.by(1)
        expect { result }.not_to change(Entitlement::EntitlementValue, :count)
      end
    end

    context "when value is boolean" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
      let(:entitlements_params) do
        {
          "seats" => {
            "enabled" => true
          }
        }
      end

      it "converts boolean to string" do
        result
        entitlement_value = plan.entitlements.first.values.first
        expect(entitlement_value.value).to eq("true")
      end
    end

    context "when value is string" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "provider", value_type: "string") }
      let(:entitlements_params) do
        {
          "seats" => {
            "provider" => "okta"
          }
        }
      end

      it "converts string to string" do
        result
        entitlement_value = plan.entitlements.first.values.first
        expect(entitlement_value.value).to eq("okta")
      end
    end

    context "when privilege value is invalid" do
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => [12, 13]
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages[:max_privilege_value]).to eq(["value_is_invalid"])
      end
    end

    context "when privilege value is not in select_options" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "invitation", value_type: "select", config: {select_options: ["email", "phone", "slack"]}) }
      let(:entitlements_params) do
        {
          "seats" => {
            "invitation" => "okta"
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages[:invitation_privilege_value]).to eq(["value_not_in_select_options"])
      end
    end
  end
end
