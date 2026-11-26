# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FeaturesController do
  let_it_be(:organization) { create_default(:organization) }
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

  def indexed_privileges
    json[:feature][:privileges].index_by { it[:code].to_sym }
  end

  describe "POST /api/v1/features" do
    subject { post_with_token(organization, "/api/v1/features", params) }

    let(:params) do
      {
        feature: {
          code: "new_feature",
          name: "New Feature",
          description: "A new feature",
          privileges: [
            {code: "priv1", value_type: "string"},
            {code: "priv2", name: "Maximum", value_type: "integer"},
            {code: "priv3", value_type: "boolean"},
            {code: "priv4", name: "SELECT", value_type: "select", config: {select_options: %w[a b c]}}
          ]
        }
      }
    end

    it "creates a new feature with privileges" do
      expect { subject }.to change(organization.features, :count).by(1)
        .and change(organization.privileges, :count).by(4)

      expect(response).to have_http_status(:success)
      expect(json[:feature][:code]).to eq("new_feature")
      expect(json[:feature][:name]).to eq("New Feature")
      expect(json[:feature][:description]).to eq("A new feature")
      expect(json[:feature][:privileges]).to contain_exactly(
        {code: "priv1", name: nil, value_type: "string", config: {}},
        {code: "priv2", name: "Maximum", value_type: "integer", config: {}},
        {code: "priv3", name: nil, value_type: "boolean", config: {}},
        {code: "priv4", name: "SELECT", value_type: "select", config: {select_options: %w[a b c]}}
      )
    end

    context "when feature code already exists" do
      let(:params) do
        {
          feature: {
            code: "seats", # Already exists
            name: "New Feature",
            description: "A new feature"
          }
        }
      end

      it "returns validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to include("validation_errors")
      end
    end

    context "when feature code is missing" do
      let(:params) do
        {
          feature: {
            name: "New Feature",
            description: "A new feature"
          }
        }
      end

      it "returns validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to include("validation_errors")
      end
    end

    context "when feature code is empty string" do
      let(:params) do
        {
          feature: {
            code: "",
            name: "New Feature",
            description: "A new feature"
          }
        }
      end

      it "returns validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to include("validation_errors")
      end
    end

    context "when privilege value_type is invalid" do
      let(:params) do
        {
          feature: {
            code: "new_feature",
            privileges: [
              {code: "max_admins", value_type: "invalid_type"}
            ]
          }
        }
      end

      it "returns validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:"privilege.value_type"]).to eq ["value_is_invalid"]
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, code|
      context "when the feature code is #{label}" do
        let(:params) { {feature: {code:, name: "New Feature"}} }

        it "returns a validation error and creates nothing" do
          expect { subject }.not_to change(organization.features, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:code]).to eq ["value_is_invalid"]
        end
      end

      context "when a privilege code is #{label}" do
        let(:params) { {feature: {code: "test", privileges: [{code:, value_type: "string"}]}} }

        it "returns a validation error and creates nothing" do
          expect { subject }.to not_change(organization.features, :count).and not_change(organization.privileges, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:"privilege.code"]).to eq ["value_is_invalid"]
        end
      end
    end

    context "when privilege code is empty string" do
      let(:params) do
        {
          feature: {
            code: "test",
            name: "New Feature",
            description: "A new feature",
            privileges: [{
              code: " "
            }]
          }
        }
      end

      it "returns validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to include("validation_errors")
      end
    end

    context "with 50 privileges" do
      let(:params) { {feature: {code: "new_feature", privileges: Array.new(50) { |i| {code: "priv_#{i}"} }}} }

      it "creates the feature with its 50 privileges" do
        expect { subject }.to change(organization.privileges, :count).by(50)

        expect(response).to have_http_status(:success)
        expect(json[:feature][:privileges].size).to eq(50)
      end
    end

    context "with 51 privileges" do
      let(:params) { {feature: {code: "new_feature", privileges: Array.new(51) { |i| {code: "priv_#{i}"} }}} }

      it "returns too_many_privileges and creates nothing" do
        expect { subject }.to not_change(organization.features, :count).and not_change(organization.privileges, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["too_many_privileges"])
      end
    end

    context "when privileges is a single object instead of an array" do
      let(:params) { {feature: {code: "new_feature", privileges: {code: "seats", value_type: "boolean"}}} }

      it "returns a validation error on privileges and creates nothing" do
        expect { subject }.to not_change(organization.features, :count).and not_change(organization.privileges, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details]).to eq(privileges: ["value_is_invalid"])
      end
    end

    context "when privileges is an object with numeric keys" do
      let(:params) { {feature: {code: "new_feature", privileges: {"0" => {code: "a"}, "1" => {code: "b"}}}} }

      it "returns a validation error on privileges and creates nothing" do
        expect { subject }
          .to not_change(organization.features, :count)
          .and not_change(organization.privileges, :count)
          .and not_have_enqueued_job(SendWebhookJob)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details]).to eq(privileges: ["value_is_invalid"])
      end
    end

    # Strong params reduce these hashes to {}: they are ignored, as before.
    [
      ["an empty object", {}],
      ["an object keyed by privilege code", {seats: {value_type: "boolean"}}],
      ["null", nil]
    ].each do |label, privileges|
      context "when privileges is #{label}" do
        let(:params) { {feature: {code: "new_feature", name: "New Feature", privileges:}} }

        it "creates the feature without privileges" do
          expect { subject }.to change(organization.features, :count).by(1).and not_change(organization.privileges, :count)

          expect(response).to have_http_status(:success)
          expect(json[:feature][:code]).to eq("new_feature")
          expect(json[:feature][:name]).to eq("New Feature")
          expect(json[:feature][:privileges]).to eq([])
        end
      end
    end

    context "when feature has no privileges" do
      let(:params) do
        {
          feature: {
            code: "new_feature",
            name: "New Feature",
            description: "A new feature"
          }
        }
      end

      it "creates a feature without privileges" do
        expect { subject }.to change(Entitlement::Feature, :count).by(1).and(not_change(Entitlement::Privilege, :count))

        expect(response).to have_http_status(:success)
        expect(json[:feature][:code]).to eq("new_feature")
        expect(json[:feature][:privileges]).to eq([])
      end
    end

    context "when feature name and description are optional" do
      let(:params) do
        {
          feature: {
            code: "new_feature",
            privileges: [
              {code: "max_admins", value_type: "integer"}
            ]
          }
        }
      end

      it "creates a feature with only required attributes" do
        expect { subject }.to change(Entitlement::Feature, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:feature][:code]).to eq("new_feature")
        expect(json[:feature][:name]).to be_nil
        expect(json[:feature][:description]).to be_nil
      end
    end
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

      expect(feature_response[:privileges]).to contain_exactly(
        {code: "max_admins", name: "", value_type: "integer", config: {}},
        {code: "max", name: "Maximum", value_type: "integer", config: {}}
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

    context "with search_term" do
      let(:params) { {search_term: "sto"} }

      it "returns features matching the search term" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:features].count).to eq(1)
        expect(json[:features].first[:code]).to eq("storage")
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
      expect(json[:feature][:privileges]).to contain_exactly(
        {code: "max_admins", name: "", value_type: "integer", config: {}},
        {code: "max", name: "Maximum", value_type: "integer", config: {}}
      )
    end

    context "when feature does not exist" do
      let(:feature_code) { "non_existent" }

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

  describe "PATCH /api/v1/features/:code" do
    subject { patch_with_token(organization, "/api/v1/features/#{feature_code}", params) }

    let(:feature_code) { feature1.code }
    let(:params) do
      {
        feature: {
          name: "Updated Feature Name",
          description: "Updated feature description",
          privileges: [
            {code: "max", name: "Max."}
          ]
        }
      }
    end

    it "updates the feature and privilege attributes" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:feature][:name]).to eq("Updated Feature Name")
      expect(json[:feature][:description]).to eq("Updated feature description")
      expect(indexed_privileges[:max][:name]).to eq("Max.")
      expect(indexed_privileges[:max_admins][:name]).to eq("") # unchanged
    end

    it "only updates provided attributes" do
      original_name = feature1.name
      params[:feature].delete(:name)

      subject

      expect(response).to have_http_status(:ok)
      expect(json[:feature][:name]).to eq(original_name)
      expect(json[:feature][:description]).to eq("Updated feature description")
    end

    [["a number", 123], ["a boolean", true]].each do |label, code|
      it "returns a validation error when a new privilege code is #{label}" do
        params[:feature][:privileges] << {code:, name: "New Name"}

        expect { subject }.not_to change(organization.privileges, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:"privilege.code"]).to eq ["value_is_invalid"]
      end
    end

    it "creates privilege non existent privilege" do
      params[:feature][:privileges] << {code: "nonexistent", name: "New Name"}

      subject

      expect(response).to have_http_status(:ok)
      expect(indexed_privileges[:max][:name]).to eq("Max.")
      expect(indexed_privileges[:nonexistent][:name]).to eq("New Name")
    end

    %i[patch put].each do |verb|
      context "when a privilege code is padded with spaces and sent with #{verb.upcase}" do
        subject { public_send(:"#{verb}_with_token", organization, "/api/v1/features/#{feature_code}", params) }

        let(:privilege2) do
          create(:privilege, feature: feature1, code: "max", name: "Maximum", value_type: "select", config: {select_options: %w[one two]})
        end
        let(:plan_value) { create(:entitlement_value, entitlement: create(:entitlement, feature: feature1), privilege: privilege2, value: "one") }
        let(:subscription_value) do
          create(:entitlement_value, entitlement: create(:entitlement, :subscription, feature: feature1), privilege: privilege2, value: "two")
        end
        let(:params) { {feature: {privileges: [{code: " max ", name: "New"}]}} }

        before do
          plan_value
          subscription_value
        end

        it "renames the stored privilege in place and keeps its entitlement values" do
          expect { subject }.not_to change(Entitlement::Privilege.with_discarded, :count)

          expect(response).to have_http_status(:ok)
          expect(indexed_privileges[:max]).to include(name: "New", config: {select_options: %w[one two]})
          expect(feature1.privileges.reload.pluck(:id, :code, :name)).to match_array([
            [privilege1.id, "max_admins", ""],
            [privilege2.id, "max", "New"]
          ])
          expect(Entitlement::EntitlementValue.where(privilege: privilege2)).to match_array([plan_value, subscription_value])
        end
      end
    end

    %i[patch put].each do |verb|
      [
        ["a single object", {code: "max", name: "New", value_type: "boolean"}],
        ["an object with numeric keys", {"0" => {code: "max", name: "New"}, "1" => {code: "other"}}]
      ].each do |label, privileges|
        context "when privileges is #{label} and sent with #{verb.upcase}" do
          subject { public_send(:"#{verb}_with_token", organization, "/api/v1/features/#{feature_code}", params) }

          let(:params) { {feature: {name: "Updated Name", description: "Updated description", privileges:}} }

          it "returns a validation error on privileges and changes nothing" do
            expect { subject }
              .to not_change { feature1.reload.attributes.slice("name", "description") }
              .and not_change { feature1.privileges.reload.pluck(:id, :code, :name) }
              .and not_have_enqueued_job(SendWebhookJob)

            expect(response).to have_http_status(:unprocessable_content)
            expect(json[:code]).to eq("validation_errors")
            expect(json[:error_details]).to eq(privileges: ["value_is_invalid"])
          end
        end
      end

      # Strong params reduce these hashes to {}: they are ignored, as before.
      [
        ["an empty object", {}],
        ["an object keyed by privilege code", {max: {name: "New"}}],
        ["null", nil]
      ].each do |label, privileges|
        context "when privileges is #{label} and sent with #{verb.upcase}" do
          subject { public_send(:"#{verb}_with_token", organization, "/api/v1/features/#{feature_code}", params) }

          let(:params) { {feature: {name: "Updated Name", privileges:}} }

          it "updates the feature and leaves its privileges unchanged" do
            expect { subject }.not_to change { feature1.privileges.reload.pluck(:id, :code, :name) }

            expect(response).to have_http_status(:ok)
            expect(json[:feature][:name]).to eq("Updated Name")
            expect(feature1.reload.name).to eq("Updated Name")
          end
        end
      end
    end

    context "when updating only feature attributes" do
      let(:params) do
        {
          feature: {
            name: "Updated Feature Name",
            description: "Updated feature description"
          }
        }
      end

      it "updates only feature attributes" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:feature][:name]).to eq("Updated Feature Name")
        expect(json[:feature][:description]).to eq("Updated feature description")
        expect(indexed_privileges[:max][:name]).to eq("Maximum") # unchanged
      end
    end

    context "when updating only privilege names" do
      let(:params) do
        {
          feature: {
            privileges: [
              {code: "max", name: "Max."},
              {code: "max_admins", name: "Max Admins"}
            ]
          }
        }
      end

      it "updates only privilege names" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:feature][:name]).to eq("Number of seats") # unchanged
        expect(json[:feature][:description]).to eq("Number of users of the account") # unchanged
        expect(indexed_privileges[:max][:name]).to eq("Max.")
        expect(indexed_privileges[:max_admins][:name]).to eq("Max Admins")
      end
    end

    context "when the update adds 48 privileges to the 2 existing ones" do
      let(:params) { {feature: {privileges: Array.new(48) { |i| {code: "priv_#{i}"} }}} }

      it "ends with 50 privileges" do
        expect { subject }.to change(organization.privileges, :count).by(48)

        expect(response).to have_http_status(:ok)
        expect(json[:feature][:privileges].size).to eq(50)
      end
    end

    context "when the update adds 49 privileges to the 2 existing ones" do
      let(:params) { {feature: {name: "Renamed", privileges: Array.new(49) { |i| {code: "priv_#{i}"} }}} }

      it "returns too_many_privileges and writes nothing" do
        expect { subject }.not_to change(organization.privileges, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["too_many_privileges"])
        expect(feature1.reload.name).to eq("Number of seats")
      end
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

    context "when privilege name is empty" do
      let(:params) do
        {
          feature: {
            privileges: [
              {code: "max", name: ""} # Empty name is allowed
            ]
          }
        }
      end

      it "updates the privilege name to empty string" do
        subject

        expect(response).to have_http_status(:ok)
        expect(indexed_privileges[:max][:name]).to eq("")
      end
    end

    context "when feature name is empty" do
      let(:params) do
        {
          feature: {
            name: "" # Empty name is allowed
          }
        }
      end

      it "updates the feature name to empty string" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:feature][:name]).to eq("")
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
end
