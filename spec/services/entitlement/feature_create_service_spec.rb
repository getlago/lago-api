# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeatureCreateService do
  subject { described_class.call(organization:, params:) }

  let_it_be(:organization) { create(:organization) }
  let(:params) do
    {
      code: "seats",
      name: "Number of seats",
      description: "Number of users of the account",
      privileges: [
        {code: "max_admins", value_type: "integer"},
        {code: "max", name: "Maximum", value_type: "integer"}
      ]
    }
  end

  describe "#call", :premium do
    [["a number", 123], ["a boolean", true]].each do |label, code|
      context "when the code is #{label}" do
        let(:params) { {code:} }

        it "returns a validation failure and creates nothing" do
          expect { subject }.not_to change(Entitlement::Feature, :count)

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({code: ["value_is_invalid"]})
        end
      end
    end

    it "creates a feature with the provided attributes" do
      expect { subject }.to change(Entitlement::Feature, :count).by(1)

      result = subject
      expect(result).to be_success
      expect(result.feature.code).to eq("seats")
      expect(result.feature.name).to eq("Number of seats")
      expect(result.feature.description).to eq("Number of users of the account")
      expect(result.feature.organization).to eq(organization)
    end

    it "trims code" do
      params[:code] = "  seats  "
      params[:privileges] = [{code: "  test "}]
      result = subject
      expect(result.feature.code).to eq "seats"
      expect(result.feature.privileges.sole.code).to eq "test"
    end

    it "produces an activity log" do
      result = subject
      expect(Utils::ActivityLog).to have_produced("feature.created").after_commit.with(result.feature)
    end

    it "sends feature.created webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.created", instance_of(Entitlement::Feature))
    end

    it "creates privileges for the feature" do
      expect { subject }.to change(Entitlement::Privilege, :count).by(2)

      result = subject
      expect(result).to be_success

      privileges = result.feature.privileges
      expect(privileges.count).to eq(2)

      max_admins_privilege = privileges.find_by(code: "max_admins")
      expect(max_admins_privilege.value_type).to eq("integer")
      expect(max_admins_privilege.name).to be_nil

      max_privilege = privileges.find_by(code: "max")
      expect(max_privilege.value_type).to eq("integer")
      expect(max_privilege.name).to eq("Maximum")
    end

    context "when organization is nil" do
      let(:organization) { nil }

      it "returns a not found failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("organization")
      end
    end

    context "when feature code is invalid" do
      let(:params) do
        {
          code: "", # Invalid empty code
          name: "Number of seats",
          description: "Number of users of the account"
        }
      end

      it "returns a validation failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:code]).to eq ["value_is_mandatory"]
      end
    end

    context "when feature code already exists" do
      before do
        create(:feature, organization:, code: "seats")
      end

      it "returns a validation failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:code]).to eq ["value_already_exist"]
      end
    end

    context "when privilege value_type is not set" do
      let(:params) do
        {
          code: "seats",
          name: "Number of seats",
          description: "Number of users of the account",
          privileges: [
            {code: "max_admins"}
          ]
        }
      end

      it "defaults to string" do
        result = subject

        expect(result).to be_success
        expect(result.feature.privileges.sole.value_type).to eq "string"
      end
    end

    context "when privilege code is duplicated" do
      let(:params) do
        {
          code: "seats",
          privileges: [
            {code: "max_admins"},
            {code: "max_admins"}
          ]
        }
      end

      it "returns a validation failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
      end
    end

    context "when two privilege codes are equal once stripped" do
      let(:params) { {code: "seats", privileges: [{code: "max"}, {code: " max "}]} }

      it "returns a validation failure and creates nothing" do
        result = subject

        expect(result).not_to be_success
        expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
        expect(Entitlement::Feature.count).to eq(0)
        expect(Entitlement::Privilege.count).to eq(0)
      end
    end

    context "with 50 privileges" do
      let(:params) { {code: "seats", privileges: Array.new(50) { |i| {code: "privilege_#{i}"} }} }

      it "creates the feature with its 50 privileges" do
        result = subject

        expect(result).to be_success
        expect(result.feature.privileges.count).to eq(50)
      end
    end

    context "with 51 privileges" do
      let(:params) { {code: "seats", privileges: Array.new(51) { |i| {code: "privilege_#{i}"} }} }

      it "returns too_many_privileges and creates nothing" do
        expect { subject }
          .to not_change(Entitlement::Feature, :count)
          .and not_change(Entitlement::Privilege, :count)
          .and not_have_enqueued_job(SendWebhookJob)

        expect(subject).to be_failure
        expect(subject.error).to be_a(BaseService::ValidationFailure)
        expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
        expect(subject.error.meta).to eq({base: {max_items: 50}})
      end
    end

    [
      ["a single object", {code: "seats", value_type: "boolean"}],
      ["an object with numeric keys", {"0" => {code: "a"}, "1" => {code: "b"}}]
    ].each do |label, privileges|
      context "when privileges is #{label}" do
        let(:params) { {code: "seats", privileges:} }

        it "returns value_is_invalid on privileges and creates nothing" do
          expect { subject }
            .to not_change(Entitlement::Feature, :count)
            .and not_change(Entitlement::Privilege, :count)
            .and not_have_enqueued_job(SendWebhookJob)

          expect(subject).to be_failure
          expect(subject.error).to be_a(BaseService::ValidationFailure)
          expect(subject.error.messages).to eq({privileges: ["value_is_invalid"]})
        end
      end
    end

    context "when privileges is an empty hash" do
      let(:params) { {code: "seats", privileges: {}} }

      it "creates the feature without privileges" do
        expect { subject }.to change(Entitlement::Feature, :count).by(1).and not_change(Entitlement::Privilege, :count)

        expect(subject).to be_success
      end
    end

    context "when privilege value_type is invalid" do
      let(:params) do
        {
          code: "seats",
          name: "Number of seats",
          description: "Number of users of the account",
          privileges: [
            {code: "max_admins", value_type: "invalid_type"}
          ]
        }
      end

      it "returns a validation failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:"privilege.value_type"]).to eq ["value_is_invalid"]
      end
    end

    context "when privilege code is invalid" do
      let(:params) do
        {
          code: "seats",
          name: "Number of seats",
          description: "Number of users of the account",
          privileges: [
            {value_type: "integer"} # Invalid empty code
          ]
        }
      end

      it "returns a validation failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:"privilege.code"]).to eq ["value_is_mandatory"]
      end
    end

    context "when feature has no privileges" do
      let(:params) do
        {
          code: "seats",
          name: "Number of seats",
          description: "Number of users of the account"
        }
      end

      it "creates a feature without privileges" do
        expect { subject }.to change(Entitlement::Feature, :count).by(1).and(not_change(Entitlement::Privilege, :count))

        result = subject
        expect(result).to be_success
        expect(result.feature.privileges).to be_empty
      end
    end

    context "when feature name and description, and privilege name are optional" do
      let(:params) do
        {
          code: "seats",
          privileges: [
            {code: "max_admins", value_type: "integer"}
          ]
        }
      end

      it "creates a feature with only required attributes" do
        expect { subject }.to change(Entitlement::Feature, :count).by(1)

        result = subject
        expect(result).to be_success
        expect(result.feature.code).to eq("seats")
        expect(result.feature.name).to be_nil
        expect(result.feature.description).to be_nil
      end
    end

    context "when privilege has config" do
      let(:params) do
        {
          code: "sso",
          privileges: [
            {
              code: "provider",
              name: "Provider Name",
              value_type: "select",
              config: {select_options: %w[okta ad google custom]}
            }
          ]
        }
      end

      it "creates privilege with config" do
        expect { subject }.to change(Entitlement::Privilege, :count).by(1)

        result = subject
        expect(result).to be_success

        privilege = result.feature.privileges.first
        expect(privilege.code).to eq("provider")
        expect(privilege.name).to eq("Provider Name")
        expect(privilege.value_type).to eq("select")
        expect(privilege.config).to eq({"select_options" => %w[okta ad google custom]})
      end
    end
  end
end
