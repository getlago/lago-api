# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeaturePartialUpdateService, type: :service do
  subject { described_class.call(feature:, params:) }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege1) { create(:privilege, feature:, code: "max", name: "Maximum") }
  let(:privilege2) { create(:privilege, feature:, code: "min", name: "Minimum") }

  before do
    privilege1
    privilege2
  end

  describe "#call" do
    context "when updating feature attributes" do
      let(:params) do
        {
          name: "Updated Feature Name",
          description: "Updated feature description"
        }
      end

      it "updates the feature name and description" do
        result = subject

        expect(result).to be_success
        expect(result.feature.name).to eq("Updated Feature Name")
        expect(result.feature.description).to eq("Updated feature description")
      end

      it "sends feature.updated webhook" do
        expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
      end

      it "only updates provided attributes" do
        original_name = feature.name
        params.delete(:name)

        result = subject

        expect(result).to be_success
        expect(result.feature.name).to eq(original_name)
        expect(result.feature.description).to eq("Updated feature description")
      end
    end

    context "when updating privilege names" do
      let(:params) do
        {
          privileges: {
            "max" => {name: "Max."},
            "min" => {name: "Min."}
          }
        }
      end

      it "updates the privilege names" do
        result = subject

        expect(result).to be_success
        expect(privilege1.reload.name).to eq("Max.")
        expect(privilege2.reload.name).to eq("Min.")
      end

      it "only updates privileges that exist" do
        params[:privileges]["nonexistent"] = {name: "New Name"}

        result = subject

        expect(result).to be_success
        expect(privilege1.reload.name).to eq("Max.")
        expect(privilege2.reload.name).to eq("Min.")
      end

      it "only updates provided privilege attributes" do
        original_name = privilege1.name
        params[:privileges]["max"].delete(:name)

        result = subject

        expect(result).to be_success
        expect(privilege1.reload.name).to eq(original_name)
        expect(privilege2.reload.name).to eq("Min.")
      end
    end

    context "when updating both feature and privileges" do
      let(:params) do
        {
          name: "Updated Feature Name",
          description: "Updated feature description",
          privileges: {
            "max" => {name: "Max."}
          }
        }
      end

      it "updates both feature and privilege attributes" do
        result = subject

        expect(result).to be_success
        expect(result.feature.name).to eq("Updated Feature Name")
        expect(result.feature.description).to eq("Updated feature description")
        expect(privilege1.reload.name).to eq("Max.")
        expect(privilege2.reload.name).to eq("Minimum") # unchanged
      end
    end

    context "when feature is nil" do
      let(:params) { {name: "Updated Name"} }

      it "returns a not found failure" do
        result = described_class.call(feature: nil, params:)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when privilege name is empty" do
      let(:params) do
        {
          privileges: {
            "max" => {name: ""} # Empty name is allowed
          }
        }
      end

      it "updates the privilege name to empty string" do
        result = subject

        expect(result).to be_success
        expect(privilege1.reload.name).to eq("")
      end
    end

    context "when feature name is empty" do
      let(:params) { {name: ""} }

      it "updates the feature name to empty string" do
        result = subject

        expect(result).to be_success
        expect(result.feature.name).to eq("")
      end
    end

    context "when new privileges is provided" do
      let(:new_privilege_code) { "new_privilege" }
      let(:params) do
        {
          privileges: {
            new_privilege_code => {name: "New Privilege"}
          }
        }
      end

      it "creates a new privilege" do
        result = subject

        expect(result).to be_success
        expect(feature.privileges.reload.count).to eq(3) # 2 existing + 1 new
        expect(feature.privileges.find_by(code: new_privilege_code).name).to eq("New Privilege")
      end

      context "when new privilege params are invalid" do
        let(:params) do
          {
            privileges: {
              new_privilege_code => {name: "New Privilege", value_type: "invalid_type"}
            }
          }
        end

        it "returns a validation failure" do
          result = subject

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to include("privilege.value_type": ["value_is_invalid"])
        end
      end
    end

    context "when feature is attached to a plan" do
      let(:params) { {} }
      let(:entitlement) { create(:entitlement, feature:) }
      let(:privilege1_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 10) }
      let(:privilege2_value) { create(:entitlement_value, entitlement:, privilege: privilege2, value: true) }

      before do
        privilege1_value
        privilege2_value
      end

      it "discard all values and entitlement" do
        expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
      end
    end
  end
end
