# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::UsageAttributionTypesController do
  let(:organization) { create(:organization, feature_flags: ["account_tree"]) }
  let(:department) do
    create(:usage_attribution_type, organization:, code: "department", name: "Department", attribution_keys: ["department_id"])
  end

  describe "POST /api/v1/usage_attribution_types" do
    subject { post_with_token(organization, "/api/v1/usage_attribution_types", params) }

    let(:params) do
      {
        usage_attribution_type: {
          code: "user",
          name: "User",
          attribution_keys: ["user_id"],
          role: "hierarchical"
        }
      }
    end

    it "creates a usage attribution type" do
      expect { subject }.to change(organization.usage_attribution_types, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(json[:usage_attribution_type]).to include(
        lago_organization_id: organization.id,
        code: "user",
        name: "User",
        attribution_keys: ["user_id"],
        role: "hierarchical",
        lago_parent_id: nil,
        parent_code: nil
      )
    end

    context "with a parent_code" do
      let(:params) do
        {
          usage_attribution_type: {
            code: "user",
            attribution_keys: ["user_id"],
            role: "hierarchical",
            parent_code: department.code
          }
        }
      end

      it "attaches the type to the parent" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:usage_attribution_type][:lago_parent_id]).to eq(department.id)
        expect(json[:usage_attribution_type][:parent_code]).to eq("department")
      end
    end

    context "with an unknown parent_code" do
      let(:params) do
        {
          usage_attribution_type: {
            code: "user",
            attribution_keys: ["user_id"],
            role: "hierarchical",
            parent_code: "unknown"
          }
        }
      end

      it "returns a not found error" do
        expect { subject }.not_to change(organization.usage_attribution_types, :count)

        expect(response).to be_not_found_error("parent_usage_attribution_type")
      end
    end

    context "with a parent_code belonging to another organization" do
      let(:other_parent) { create(:usage_attribution_type, code: "other") }
      let(:params) do
        {
          usage_attribution_type: {
            code: "user",
            attribution_keys: ["user_id"],
            role: "hierarchical",
            parent_code: other_parent.code
          }
        }
      end

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("parent_usage_attribution_type")
      end
    end

    context "when the code is already taken" do
      let(:params) do
        {
          usage_attribution_type: {
            code: department.code,
            attribution_keys: ["another_key"],
            role: "hierarchical"
          }
        }
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:code]).to eq(["value_already_exist"])
      end
    end

    context "when the role is invalid" do
      let(:params) do
        {
          usage_attribution_type: {
            code: "user",
            attribution_keys: ["user_id"],
            role: "unknown"
          }
        }
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:role]).to eq(["value_is_invalid"])
      end
    end

    context "when the payload root is missing" do
      let(:params) { {} }

      it "returns a bad request error" do
        subject

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when the account_tree feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        expect { subject }.not_to change(organization.usage_attribution_types, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v1/usage_attribution_types" do
    subject { get_with_token(organization, "/api/v1/usage_attribution_types", params) }

    let(:params) { {} }
    let(:model) { create(:flat_usage_attribution_type, organization:, code: "model", attribution_keys: ["model_name"]) }

    before do
      department
      model
    end

    it "returns the usage attribution types of the organization" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:usage_attribution_types].pluck(:code)).to match_array(%w[department model])
      expect(json[:meta][:total_count]).to eq(2)
    end

    context "with a role filter" do
      let(:params) { {role: "flat"} }

      it "returns only the matching types" do
        subject

        expect(json[:usage_attribution_types].pluck(:code)).to eq(["model"])
      end
    end

    context "with an invalid role filter" do
      let(:params) { {role: "unknown"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with a search term" do
      let(:params) { {search_term: "depart"} }

      it "returns only the matching types" do
        subject

        expect(json[:usage_attribution_types].pluck(:code)).to eq(["department"])
      end
    end

    context "when the account_tree feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/usage_attribution_types/:code" do
    subject { get_with_token(organization, "/api/v1/usage_attribution_types/#{code}") }

    let(:code) { department.code }

    before { department }

    it "returns the usage attribution type" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:usage_attribution_type][:lago_id]).to eq(department.id)
      expect(json[:usage_attribution_type][:code]).to eq("department")
    end

    context "when the type does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("usage_attribution_type")
      end
    end

    context "when the type belongs to another organization" do
      let(:code) { create(:usage_attribution_type, code: "foreign").code }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("usage_attribution_type")
      end
    end
  end

  describe "PUT /api/v1/usage_attribution_types/:code" do
    subject { put_with_token(organization, "/api/v1/usage_attribution_types/#{code}", params) }

    let(:user) { create(:usage_attribution_type, organization:, code: "user", name: "User", attribution_keys: ["user_id"]) }
    let(:code) { user.code }
    let(:params) { {usage_attribution_type: {name: "Seat"}} }

    before do
      department
      user
    end

    it "updates the usage attribution type" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:usage_attribution_type][:name]).to eq("Seat")
      expect(user.reload.name).to eq("Seat")
    end

    it "leaves the untouched attributes alone" do
      subject

      expect(user.reload.attribution_keys).to eq(["user_id"])
    end

    context "with a parent_code" do
      let(:params) { {usage_attribution_type: {parent_code: department.code}} }

      it "attaches the type to the parent" do
        subject

        expect(response).to have_http_status(:success)
        expect(user.reload.parent).to eq(department)
      end
    end

    context "with a blank parent_code" do
      let(:user) do
        create(:usage_attribution_type, organization:, code: "user", attribution_keys: ["user_id"], parent: department)
      end
      let(:params) { {usage_attribution_type: {parent_code: nil}} }

      it "detaches the type from its parent" do
        subject

        expect(response).to have_http_status(:success)
        expect(user.reload.parent).to be_nil
      end
    end

    context "with an unknown parent_code" do
      let(:params) { {usage_attribution_type: {parent_code: "unknown"}} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("parent_usage_attribution_type")
      end
    end

    context "when usage was already attributed to the type" do
      before { create(:usage_attribution_value, organization:, usage_attribution_type: user) }

      let(:params) { {usage_attribution_type: {attribution_keys: %w[user_id usr_id]}} }

      it "still updates the attribution keys" do
        subject

        expect(response).to have_http_status(:success)
        expect(user.reload.attribution_keys).to eq(%w[user_id usr_id])
      end

      context "when a frozen attribute is submitted" do
        let(:params) { {usage_attribution_type: {code: "seat"}} }

        it "returns a validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:code]).to eq(["usage_already_attributed"])
        end
      end
    end

    context "when the type does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("usage_attribution_type")
      end
    end
  end

  describe "DELETE /api/v1/usage_attribution_types/:code" do
    subject { delete_with_token(organization, "/api/v1/usage_attribution_types/#{code}") }

    let(:code) { department.code }

    before { department }

    it "discards the usage attribution type" do
      expect { subject }.to change { department.reload.discarded? }.from(false).to(true)

      expect(response).to have_http_status(:success)
      expect(json[:usage_attribution_type][:lago_id]).to eq(department.id)
    end

    it "discards the attached values" do
      value = create(:usage_attribution_value, organization:, usage_attribution_type: department)

      expect { subject }.to change { value.reload.discarded? }.from(false).to(true)
    end

    context "when the type does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("usage_attribution_type")
      end
    end
  end
end
