# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlan do
  subject(:catalog_plan) { build(:catalog_plan) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(catalog_plan).to belong_to(:organization)
    end
  end

  describe "validations" do
    it do
      expect(catalog_plan).to validate_presence_of(:name)
      expect(catalog_plan).to validate_presence_of(:code)
      expect(build(:catalog_plan, currency: "EUR")).to be_valid
      expect(build(:catalog_plan, currency: "INVALID")).not_to be_valid
    end
  end

  describe "soft deletion" do
    it "hides discarded records behind the default scope" do
      catalog_plan.save!
      catalog_plan.discard!

      expect(described_class.all).not_to include(catalog_plan)
      expect(described_class.with_discarded).to include(catalog_plan)
    end

    it "enforces code uniqueness per organization only on kept rows" do
      organization = create(:organization)
      first = create(:catalog_plan, organization:, code: "dup")

      expect { create(:catalog_plan, organization:, code: "dup") }.to raise_error(ActiveRecord::RecordNotUnique)

      first.discard!
      expect { create(:catalog_plan, organization:, code: "dup") }.not_to raise_error
    end
  end
end
