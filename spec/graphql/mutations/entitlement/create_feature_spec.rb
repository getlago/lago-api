# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::CreateFeature, :premium do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "features:create" }
  let(:query) do
    <<-GQL
      mutation($input: CreateFeatureInput!) {
        createFeature(input: $input) {
          id
          code
          name
          description
          privileges {
            code
            name
            valueType
          }
        }
      }
    GQL
  end
  let(:input) do
    {
      code: "test_feature",
      name: "Test Feature",
      description: "Test Feature Description",
      privileges: []
    }
  end

  let_it_be(:organization) { create_default(:organization) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "features:create"

  it "creates a feature" do
    result = subject

    result_data = result["data"]["createFeature"]

    expect(result_data["code"]).to eq("test_feature")
    expect(result_data["name"]).to eq("Test Feature")
    expect(result_data["description"]).to eq("Test Feature Description")
    expect(result_data["privileges"]).to be_empty
  end

  context "when creating feature with privileges" do
    let(:privilege_code) { "test_privilege" }
    let(:privilege_name) { "Test Privilege" }
    let(:input) do
      {
        code: "test_feature_with_privileges",
        name: "Test Feature With Privileges",
        description: "Test Feature Description",
        privileges: [
          {code: privilege_code, name: privilege_name}
        ]
      }
    end

    it "creates a feature with privileges" do
      result = subject

      result_data = result["data"]["createFeature"]

      expect(result_data["code"]).to eq("test_feature_with_privileges")
      expect(result_data["name"]).to eq("Test Feature With Privileges")
      expect(result_data["description"]).to eq("Test Feature Description")
      expect(result_data["privileges"].size).to eq(1)
      expect(result_data["privileges"].sole["code"]).to eq(privilege_code)
      expect(result_data["privileges"].sole["name"]).to eq(privilege_name)
      expect(result_data["privileges"].sole["valueType"]).to eq("string")
    end
  end

  context "with 50 privileges" do
    let(:input) { {code: "test_feature", privileges: Array.new(50) { |i| {code: "privilege_#{i}"} }} }

    it "creates the feature with its 50 privileges" do
      result = subject

      expect(result["data"]["createFeature"]["privileges"].size).to eq(50)
    end
  end

  context "with 51 privileges" do
    let(:input) { {code: "test_feature", privileges: Array.new(51) { |i| {code: "privilege_#{i}"} }} }

    it "returns too_many_privileges and creates nothing" do
      result = nil
      expect { result = subject }
        .to not_change(Entitlement::Feature, :count)
        .and not_change(Entitlement::Privilege, :count)

      expect_graphql_error(result:, message: "unprocessable_entity", details: {base: ["too_many_privileges"]})
    end
  end
end
