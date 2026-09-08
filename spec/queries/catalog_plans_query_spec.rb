# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlansQuery do
  subject(:result) { described_class.call(organization:, pagination:, search_term:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:search_term) { nil }

  let!(:catalog_plan) { create(:catalog_plan, organization:, name: "Growth", code: "growth") }

  it "returns the organization catalog plans" do
    create(:catalog_plan)

    expect(result).to be_success
    expect(result.catalog_plans).to match_array([catalog_plan])
  end

  it "preloads applied_rate_cards so the collection avoids a count per plan" do
    create(:plan_rate_card, organization:, catalog_plan:)

    expect(result.catalog_plans.first.association(:applied_rate_cards)).to be_loaded
  end

  context "with a search term" do
    let(:search_term) { "grow" }

    before { create(:catalog_plan, organization:, name: "Other", code: "other") }

    it "filters by name or code" do
      expect(result.catalog_plans).to match_array([catalog_plan])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    before { create(:catalog_plan, organization:, code: "second") }

    it "paginates the catalog plans" do
      expect(result.catalog_plans.count).to eq(1)
      expect(result.catalog_plans.current_page).to eq(2)
    end
  end
end
