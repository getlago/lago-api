# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionTypesQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, search_term:)
  end

  let(:returned_ids) { result.usage_attribution_types.pluck(:id) }
  let(:organization) { create(:organization) }
  let(:pagination) { {page: 1, limit: 10} }
  let(:filters) { {} }
  let(:search_term) { nil }

  let(:department) { create(:usage_attribution_type, organization:, code: "department", name: "Department", attribution_keys: ["department_id"]) }
  let(:user) { create(:usage_attribution_type, organization:, code: "user", name: "User", attribution_keys: ["user_id"], parent: department) }
  let(:model) { create(:flat_usage_attribution_type, organization:, code: "model", name: "Model", attribution_keys: ["model_name"]) }

  before do
    department
    user
    model
  end

  it "returns all usage attribution types of the organization" do
    expect(result).to be_success
    expect(returned_ids).to match_array([department.id, user.id, model.id])
  end

  it "does not return types of another organization" do
    other = create(:usage_attribution_type)

    expect(returned_ids).not_to include(other.id)
  end

  it "does not return discarded types" do
    model.discard!

    expect(returned_ids).to match_array([department.id, user.id])
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.usage_attribution_types.count).to eq(1)
      expect(result.usage_attribution_types.current_page).to eq(2)
      expect(result.usage_attribution_types.total_count).to eq(3)
    end
  end

  context "with a role filter" do
    let(:filters) { {role: "flat"} }

    it "returns only the flat types" do
      expect(returned_ids).to eq([model.id])
    end
  end

  context "with an invalid role filter" do
    let(:filters) { {role: "unknown"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:role]).to include("must be one of: hierarchical, flat")
    end
  end

  context "when searching by code or name" do
    let(:search_term) { "depart" }

    it "returns the matching types" do
      expect(returned_ids).to eq([department.id])
    end

    context "when the term matches a name" do
      let(:search_term) { "Model" }

      it "returns the matching types" do
        expect(returned_ids).to eq([model.id])
      end
    end

    context "when the term matches an attribution key" do
      let(:search_term) { "model_name" }

      it "returns nothing" do
        expect(returned_ids).to be_empty
      end
    end
  end
end
