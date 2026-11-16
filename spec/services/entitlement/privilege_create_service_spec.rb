# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PrivilegeCreateService do
  subject(:result) { described_class.call(feature:, params:) }

  let_it_be(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:params) { {code: "max_admins", name: "Max admins", value_type: "integer"} }

  shared_examples "a failure that creates nothing" do
    it "creates no privilege and sends no webhook" do
      expect { result }.to not_change(Entitlement::Privilege.unscoped, :count)
        .and not_have_enqueued_job(SendWebhookJob)
      expect(Utils::ActivityLog).not_to have_produced("feature.updated")
    end
  end

  shared_examples "a validation failure" do |messages, meta = nil|
    it "returns a validation failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(messages)
      expect(result.error.meta).to eq(meta) if meta
    end

    it_behaves_like "a failure that creates nothing"
  end

  describe "#call", :premium do
    it "creates the privilege on the feature" do
      expect { result }.to change(feature.privileges, :count).by(1)

      expect(result).to be_success
      expect(result.privilege).to have_attributes(
        organization_id: organization.id,
        entitlement_feature_id: feature.id,
        code: "max_admins",
        name: "Max admins",
        value_type: "integer",
        config: {}
      )
      expect(result.privilege).to be_persisted
    end

    it "sends a feature.updated webhook" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
    end

    it "produces a feature.updated activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
    end

    %w[integer string boolean].each do |type|
      context "when value_type is #{type}" do
        let(:params) { {code: "max_admins", value_type: type} }

        it "creates the privilege with an empty config" do
          expect(result).to be_success
          expect(result.privilege).to have_attributes(value_type: type, config: {}, name: nil)
        end
      end
    end

    context "when value_type is select" do
      let(:params) { {code: "level", value_type: "select", select_options: ["low", "high"]} }

      it "stores the options in the config" do
        expect(result).to be_success
        expect(result.privilege).to have_attributes(value_type: "select", config: {"select_options" => ["low", "high"]})
      end
    end

    context "when value_type is absent" do
      let(:params) { {code: "max_admins"} }

      it "defaults to string" do
        expect(result).to be_success
        expect(result.privilege.value_type).to eq("string")
      end
    end

    context "when value_type is nil" do
      let(:params) { {code: "max_admins", value_type: nil} }

      it "defaults to string" do
        expect(result).to be_success
        expect(result.privilege.value_type).to eq("string")
      end
    end

    context "when the code has surrounding spaces" do
      let(:params) { {code: "  max_admins  "} }

      it "strips the code" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when feature is nil" do
      let(:feature) { nil }

      it "returns a not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end

      it_behaves_like "a failure that creates nothing"
    end

    context "when the feature is discarded between its lookup and the lock" do
      before do
        feature
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Feature.find(feature.id).discard!
      end

      it "returns a not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end

      it_behaves_like "a failure that creates nothing"
    end

    context "when value_type is unknown" do
      let(:params) { {code: "max_admins", value_type: "float"} }

      it_behaves_like "a validation failure",
        {value_type: ["value_is_invalid"]},
        {value_type: {allowed_values: %w[integer string boolean select]}}
    end

    context "when value_type is not a string" do
      let(:params) { {code: "max_admins", value_type: 1} }

      it_behaves_like "a validation failure",
        {value_type: ["value_is_invalid"]},
        {value_type: {allowed_values: %w[integer string boolean select]}}
    end

    [["a number", 123], ["a boolean", true], ["an array", ["max_admins"]], ["an object", {a: 1}]].each do |label, value|
      context "when code is #{label}" do
        let(:params) { {code: value} }

        it_behaves_like "a validation failure", {code: ["value_is_invalid"]}
      end

      context "when name is #{label}" do
        let(:params) { {code: "max_admins", name: value} }

        it_behaves_like "a validation failure", {name: ["value_is_invalid"]}
      end
    end

    context "when value_type is an array" do
      let(:params) { {code: "max_admins", value_type: ["select"]} }

      it_behaves_like "a validation failure",
        {value_type: ["value_is_invalid"]},
        {value_type: {allowed_values: %w[integer string boolean select]}}
    end

    context "when the model refuses the config built from select_options" do
      let(:params) { {code: "level", value_type: "select", select_options: ["low"]} }

      before do
        # Stands for a model rule the select_options pre-check does not know yet.
        allow(Entitlement::ValidatePrivilegeSelectOptionsService).to receive(:call)
          .and_return(Entitlement::ValidatePrivilegeSelectOptionsService::Result.new.tap { it.config = {"select_options" => [1]} })
      end

      it_behaves_like "a validation failure", {select_options: ["invalid_format"]}
    end

    context "when select_options are refused" do
      let(:params) { {code: "level", value_type: "select"} }

      it_behaves_like "a validation failure", {select_options: ["value_is_mandatory"]}
    end

    context "when select_options are sent with another value_type" do
      let(:params) { {code: "level", value_type: "string", select_options: ["a"]} }

      it_behaves_like "a validation failure", {select_options: ["value_must_be_blank"]}
    end

    context "when code is blank" do
      let(:params) { {code: "  "} }

      it_behaves_like "a validation failure", {code: ["value_is_mandatory"]}
    end

    context "when code is absent" do
      let(:params) { {name: "Max admins"} }

      it_behaves_like "a validation failure", {code: ["value_is_mandatory"]}
    end

    context "when code is too long" do
      let(:params) { {code: "a" * 256} }

      it_behaves_like "a validation failure", {code: ["value_is_too_long"]}, {code: {max_length: 255}}
    end

    context "when name is too long" do
      let(:params) { {code: "max_admins", name: "a" * 256} }

      it_behaves_like "a validation failure", {name: ["value_is_too_long"]}, {name: {max_length: 255}}
    end

    context "when the code is used by a kept privilege of the feature, as after a concurrent create" do
      # The model has no uniqueness validation, so a kept privilege with the code stands for the winner:
      # the insert reaches idx_privileges_code_unique_per_feature.
      before { create(:privilege, feature:, organization:, code: "max_admins") }

      it_behaves_like "a validation failure", {code: ["value_already_exist"]}
    end

    context "when another unique index is violated" do
      before do
        allow_any_instance_of(Entitlement::Privilege).to receive(:save!) # rubocop:disable RSpec/AnyInstance
          .and_raise(ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint \"other_index\"")
      end

      it "raises the violation" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "when the code is used by a discarded privilege of the feature" do
      before { create(:privilege, feature:, organization:, code: "max_admins", deleted_at: Time.current) }

      it "creates the privilege" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when the code is used on another feature" do
      before { create(:privilege, organization:, feature: create(:feature, organization:), code: "max_admins") }

      it "creates the privilege" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when the feature has 49 privileges" do
      before { create_list(:privilege, 49, feature:, organization:) }

      it "creates the 50th privilege" do
        expect(result).to be_success
        expect(feature.privileges.count).to eq(50)
      end
    end

    context "when the feature has 50 kept privileges" do
      before { create_list(:privilege, 50, feature:, organization:) }

      it_behaves_like "a validation failure", {base: ["too_many_privileges"]}, {base: {max_items: 50}}
    end

    context "when the feature has 50 privileges of which one is discarded" do
      before do
        create_list(:privilege, 49, feature:, organization:)
        create(:privilege, feature:, organization:, deleted_at: Time.current)
      end

      it "creates the privilege" do
        expect(result).to be_success
        expect(feature.privileges.count).to eq(50)
      end
    end
  end
end
