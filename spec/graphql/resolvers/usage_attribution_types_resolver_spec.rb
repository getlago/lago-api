# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::UsageAttributionTypesResolver do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "usage_attribution_types:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }

  let(:department) do
    create(:usage_attribution_type, organization:, code: "department", name: "Department", attribution_keys: ["department_id"])
  end
  let(:user) do
    create(:usage_attribution_type, organization:, code: "user", name: "User", attribution_keys: ["user_id"], parent: department)
  end
  let(:model) do
    create(:flat_usage_attribution_type, organization:, code: "model", name: "Model", attribution_keys: ["model_name"])
  end

  let(:query) do
    <<~GQL
      query($limit: Int, $page: Int, $role: UsageAttributionTypeRoleEnum, $searchTerm: String) {
        usageAttributionTypes(limit: $limit, page: $page, role: $role, searchTerm: $searchTerm) {
          collection {
            id code name description attributionKeys role
            parent { id code }
          }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:collection) { result["data"]["usageAttributionTypes"]["collection"] }
  let(:metadata) { result["data"]["usageAttributionTypes"]["metadata"] }

  before do
    organization.update!(feature_flags: ["account_tree"])

    department
    user
    model
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "usage_attribution_types:view"

  it "returns the usage attribution types of the organization" do
    expect(collection.map { |type| type["id"] }).to match_array([department.id, user.id, model.id])
    expect(metadata["currentPage"]).to eq(1)
    expect(metadata["totalCount"]).to eq(3)

    hierarchical_child = collection.find { |type| type["id"] == user.id }
    expect(hierarchical_child["parent"]["id"]).to eq(department.id)
    expect(hierarchical_child["description"]).to eq(user.description)
  end

  it "does not return types of another organization" do
    other = create(:usage_attribution_type)

    expect(collection.map { |type| type["id"] }).not_to include(other.id)
  end

  it "does not return discarded types" do
    model.discard!

    expect(collection.map { |type| type["id"] }).to match_array([department.id, user.id])
  end

  context "with pagination" do
    let(:variables) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(collection.count).to eq(1)
      expect(metadata["currentPage"]).to eq(2)
      expect(metadata["totalCount"]).to eq(3)
    end
  end

  context "with a role filter" do
    let(:variables) { {role: "flat"} }

    it "returns only the matching types" do
      expect(collection.map { |type| type["id"] }).to eq([model.id])
    end
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "department"} }

    it "returns only the matching types" do
      expect(collection.map { |type| type["id"] }).to match_array([department.id])
    end
  end

  context "with the roots filter" do
    let(:team) do
      create(:usage_attribution_type, organization:, code: "team", name: "Team", attribution_keys: ["team_id"], parent: department)
    end
    let(:variables) { {roots: true} }
    let(:query) do
      <<~GQL
        query($limit: Int, $page: Int, $roots: Boolean) {
          usageAttributionTypes(limit: $limit, page: $page, roots: $roots) {
            collection {
              id code name role
              children {
                id code name role
                children { id code name role children { id } }
              }
            }
            metadata { currentPage totalCount }
          }
        }
      GQL
    end

    before do
      team
      user.update!(parent: team)
    end

    it "returns each root with its descendants nested" do
      expect(collection.map { |type| type["id"] }).to match_array([department.id, model.id])

      department_node = collection.find { |type| type["id"] == department.id }
      team_node = department_node["children"].sole
      expect(team_node["id"]).to eq(team.id)

      user_node = team_node["children"].sole
      expect(user_node["id"]).to eq(user.id)
      expect(user_node["children"]).to be_empty
    end

    it "returns a flat type as a childless root" do
      model_node = collection.find { |type| type["id"] == model.id }

      expect(model_node["role"]).to eq("flat")
      expect(model_node["children"]).to be_empty
    end

    it "paginates the roots while keeping their subtree whole" do
      expect(metadata["totalCount"]).to eq(2)
    end

    context "with pagination" do
      let(:variables) { {roots: true, page: 2, limit: 1} }

      it "returns one root with its full subtree" do
        expect(collection.count).to eq(1)
        expect(collection.first["id"]).to eq(department.id)
        expect(collection.first["children"].sole["children"].sole["id"]).to eq(user.id)
        expect(metadata["totalCount"]).to eq(2)
      end
    end

    context "when a discarded type has kept children" do
      before { department.discard! }

      it "promotes them to roots so the subtree stays visible" do
        expect(collection.map { |type| type["id"] }).to match_array([team.id, model.id])
      end
    end
  end

  context "when the account_tree feature flag is disabled" do
    before { organization.update!(feature_flags: []) }

    it "returns a forbidden error" do
      expect_graphql_error(result:, message: "forbidden")
    end

    context "when the permission is also missing" do
      let(:required_permission) { [] }

      it "returns a missing permissions error" do
        expect_graphql_error(result:, message: "Missing permissions")
      end
    end
  end
end
