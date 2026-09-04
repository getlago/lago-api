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
      expect(catalog_plan).to validate_presence_of(:currency)
      expect(build(:catalog_plan, currency: "EUR")).to be_valid
      expect(build(:catalog_plan, currency: "INVALID")).not_to be_valid
    end

    describe "code uniqueness" do
      let(:organization) { create(:organization) }

      it "rejects a duplicate code within the organization" do
        create(:catalog_plan, organization:, code: "dup")
        duplicate = build(:catalog_plan, organization:, code: "dup")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in another organization" do
        create(:catalog_plan, organization:, code: "shared")

        expect(build(:catalog_plan, organization: create(:organization), code: "shared")).to be_valid
      end

      it "frees the code once the holder is discarded" do
        create(:catalog_plan, organization:, code: "dup").discard!

        expect(build(:catalog_plan, organization:, code: "dup")).to be_valid
      end
    end
  end

  describe "soft deletion" do
    it "hides discarded records behind the default scope" do
      catalog_plan.save!
      catalog_plan.discard!

      expect(described_class.all).not_to include(catalog_plan)
      expect(described_class.with_discarded).to include(catalog_plan)
    end

    it "enforces code uniqueness among kept rows at the database level" do
      organization = create(:organization)
      create(:catalog_plan, organization:, code: "dup")
      duplicate = build(:catalog_plan, organization:, code: "dup")

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
