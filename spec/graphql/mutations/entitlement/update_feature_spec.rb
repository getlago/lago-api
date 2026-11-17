# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::UpdateFeature, :premium do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "features:update" }
  let(:feature) do
    create(:feature, organization:)
  end
  let(:query) do
    <<-GQL
      mutation($input: UpdateFeatureInput!) {
        updateFeature(input: $input) {
          id
          name
          description
          code
          privileges { code name }
        }
      }
    GQL
  end
  let(:input) do
    {
      id: feature.id,
      name: "Updated Feature Name",
      description: "Updated Feature Description",
      privileges: []
    }
  end

  let_it_be(:organization) { create_default(:organization) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:update"

  it "updates a feature" do
    result = subject

    result_data = result["data"]["updateFeature"]

    expect(result_data["name"]).to eq("Updated Feature Name")
    expect(result_data["description"]).to eq("Updated Feature Description")
    expect(result_data["code"]).to eq(feature.code)
    expect(result_data["privileges"]).to be_empty
  end

  context "when feature does not exist" do
    let(:input) do
      {
        id: "non-existent-id",
        name: "Updated Feature Name",
        description: "Updated Feature Description",
        privileges: []
      }
    end

    it "returns not found error for non-existent feature" do
      expect_graphql_error(
        result: subject,
        message: "not_found"
      )
    end
  end

  context "with privileges" do
    context "when privilege already exists" do
      let(:input) do
        {
          id: feature.id,
          name: "Feature Name",
          description: "Feature Description",
          privileges: [
            {code: "seats", name: "new name"}
          ]
        }
      end

      it "updates the privilege" do
        create(:privilege, feature:, code: "seats", name: "Old Name")

        result = subject

        result_data = result["data"]["updateFeature"]

        expect(result_data["privileges"].size).to eq(1)
        expect(result_data["privileges"].sole["code"]).to eq("seats")
        expect(result_data["privileges"].sole["name"]).to eq("new name")
      end
    end

    context "when the privilege code is padded with spaces" do
      let(:privilege) do
        create(:privilege, feature:, code: "max", name: "Old Name", value_type: "select", config: {select_options: %w[one two]})
      end
      let(:plan_value) { create(:entitlement_value, entitlement: create(:entitlement, feature:), privilege:, value: "one") }
      let(:subscription_value) do
        create(:entitlement_value, entitlement: create(:entitlement, :subscription, feature:), privilege:, value: "two")
      end
      let(:input) { {id: feature.id, privileges: [{code: " max ", name: "New Name"}]} }

      before do
        plan_value
        subscription_value
      end

      it "keeps the stored privilege, its config and its entitlement values" do
        result = subject

        expect(result["data"]["updateFeature"]["privileges"]).to eq([{"code" => "max", "name" => "New Name"}])
        expect(Entitlement::Privilege.with_discarded.where(feature:).pluck(:id, :code, :config)).to eq([
          [privilege.id, "max", {"select_options" => %w[one two]}]
        ])
        expect(Entitlement::EntitlementValue.where(privilege:)).to match_array([plan_value, subscription_value])
      end
    end

    context "when privilege is new" do
      let(:new_privilege_code) { "new_privilege" }
      let(:new_privilege_name) { "New Privilege" }
      let(:input) do
        {
          id: feature.id,
          name: "Updated Feature Name",
          description: "Updated Feature Description",
          privileges: [
            {code: new_privilege_code, name: new_privilege_name}
          ]
        }
      end

      it "adds new privileges to the feature" do
        result = subject

        result_data = result["data"]["updateFeature"]

        expect(result_data["privileges"].size).to eq(1)
        expect(result_data["privileges"].sole["code"]).to eq(new_privilege_code)
        expect(result_data["privileges"].sole["name"]).to eq(new_privilege_name)
      end
    end

    context "when the update replaces the existing privilege with 50 new ones" do
      let(:input) { {id: feature.id, privileges: Array.new(50) { |i| {code: "privilege_#{i}"} }} }

      before { create(:privilege, feature:, code: "seats") }

      it "counts the privileges after the removal" do
        result = subject

        expect(result["data"]["updateFeature"]["privileges"].size).to eq(50)
      end
    end

    context "when the update ends with 51 privileges" do
      let(:input) { {id: feature.id, name: "Renamed", privileges: Array.new(51) { |i| {code: "privilege_#{i}"} }} }

      before { create(:privilege, feature:, code: "seats") }

      it "returns too_many_privileges and writes nothing" do
        result = nil
        expect { result = subject }.not_to change(Entitlement::Privilege, :count)

        expect_graphql_error(result:, message: "unprocessable_entity", details: {base: ["too_many_privileges"]})
        expect(feature.reload.name).to eq("Feature Name")
        expect(feature.privileges.pluck(:code)).to eq(["seats"])
      end
    end
  end
end
