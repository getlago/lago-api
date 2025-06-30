# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FeaturesController, type: :request do
  let(:organization) { create(:organization) }
  let(:feature1) { create(:feature, organization:, code: "seats", name: "Number of seats", description: "Number of users of the account") }
  let(:feature2) { create(:feature, organization:, code: "storage", name: "Storage", description: "Storage space") }
  let(:privilege1) { create(:privilege, feature: feature1, code: "max_admins", name: "", value_type: "integer") }
  let(:privilege2) { create(:privilege, feature: feature1, code: "max", name: "Maximum", value_type: "integer") }

  before do
    feature1
    feature2
    privilege1
    privilege2
  end

  describe "GET /api/v1/features" do
    subject { get_with_token(organization, "/api/v1/features", params) }

    let(:params) { {} }

    it "returns a paginated list of features" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:features].length).to eq(2)

      feature_response = json[:features].find { |f| f[:code] == "seats" }
      expect(feature_response).to include(
        code: "seats",
        name: "Number of seats",
        description: "Number of users of the account"
      )

      expect(feature_response[:privileges]).to include(
        max_admins: {
          code: "max_admins",
          name: "",
          value_type: "integer"
        },
        max: {
          code: "max",
          name: "Maximum",
          value_type: "integer"
        }
      )
    end

    it "includes pagination metadata" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:meta]).to include(:current_page, :total_pages, :total_count)
    end

    it "only returns features for the current organization" do
      other_organization = create(:organization)
      create(:feature, organization: other_organization, code: "other_feature")

      subject

      expect(response).to have_http_status(:ok)
      feature_codes = json[:features].map { |f| f[:code] }
      expect(feature_codes).not_to include("other_feature")
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 1} }

      it "returns features with correct meta data" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:features].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end

  describe "GET /api/v1/features/:code" do
    subject { get_with_token(organization, "/api/v1/features/#{feature_code}") }

    let(:feature_code) { feature1.code }

    it "returns a feature" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:feature][:code]).to eq("seats")
      expect(json[:feature][:name]).to eq("Number of seats")
      expect(json[:feature][:description]).to eq("Number of users of the account")
      expect(json[:feature][:privileges]).to include(
        max_admins: {code: "max_admins", name: "", value_type: "integer"},
        max: {code: "max", name: "Maximum", value_type: "integer"}
      )
    end

    context "when feature does not exist" do
      let(:feature_code) { "non_existent" }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when feature belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_feature) { create(:feature, organization: other_organization, code: "other_feature") }
      let(:feature_code) { other_feature.code }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when feature is deleted" do
      before { feature1.discard! }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end
  end

  describe "DELETE /api/v1/features/:code" do
    subject { delete_with_token(organization, "/api/v1/features/#{feature_code}") }

    let(:feature_code) { feature1.code }

    it "discards the feature" do
      expect { subject }.to change { feature1.reload.discarded? }.from(false).to(true)
    end

    it "discards all privileges associated with the feature" do
      expect { subject }.to change { Entitlement::Privilege.kept.count }.by(-2)
    end

    it "returns the discarded feature" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:feature][:code]).to eq("seats")
      expect(json[:feature][:name]).to eq("Number of seats")
      expect(json[:feature][:description]).to eq("Number of users of the account")
    end

    context "when feature does not exist" do
      let(:feature_code) { "non_existent" }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when feature belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_feature) { create(:feature, organization: other_organization, code: "other_feature") }
      let(:feature_code) { other_feature.code }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when feature is already discarded" do
      before { feature1.discard! }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end
  end

  describe "DELETE /api/v1/features/:code/:privilege_code" do
    subject { delete_with_token(organization, "/api/v1/features/#{feature_code}/#{privilege_code}") }

    let(:feature_code) { feature1.code }
    let(:privilege_code) { privilege1.code }

    it "discards the privilege" do
      expect { subject }.to change { privilege1.reload.discarded? }.from(false).to(true)
    end

    it "returns the feature without the discarded privilege" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:feature][:code]).to eq("seats")
      expect(json[:feature][:privileges]).not_to include(:max_admins)
      expect(json[:feature][:privileges]).to include(
        max: {code: "max", name: "Maximum", value_type: "integer"}
      )
    end

    context "when feature does not exist" do
      let(:feature_code) { "non_existent" }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when privilege does not exist" do
      let(:privilege_code) { "non_existent" }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("privilege")
      end
    end

    context "when feature belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_feature) { create(:feature, organization: other_organization, code: "other_feature") }
      let(:feature_code) { other_feature.code }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("feature")
      end
    end

    context "when privilege belongs to another feature" do
      let(:other_feature) { create(:feature, organization:, code: "other_feature") }
      let(:other_privilege) { create(:privilege, feature: other_feature, code: "other_privilege") }
      let(:privilege_code) { other_privilege.code }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("privilege")
      end
    end

    context "when privilege is already discarded" do
      before { privilege1.discard! }

      it "returns not found error" do
        subject
        expect(response).to be_not_found_error("privilege")
      end
    end
  end
end
