# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::ApplyTaxesService do
  subject(:result) { described_class.call(catalog_plan:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:tax1) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:) }
  let(:tax_codes) { [tax1.code, tax2.code] }

  it "applies the organization taxes to the catalog plan" do
    expect { result }.to change(catalog_plan.applied_taxes, :count).from(0).to(2)

    expect(result).to be_success
    expect(result.applied_taxes.map(&:tax)).to match_array([tax1, tax2])
    expect(catalog_plan.reload.taxes).to match_array([tax1, tax2])
    expect(catalog_plan.applied_taxes.pluck(:organization_id).uniq).to eq([organization.id])
  end

  it "locks the catalog plan while replacing taxes" do
    allow(catalog_plan).to receive(:with_lock).and_call_original

    result

    expect(catalog_plan).to have_received(:with_lock)
  end

  context "when tax codes contain duplicates" do
    let(:tax_codes) { [tax1.code, tax1.code] }

    it "applies the tax once" do
      expect { result }.to change(catalog_plan.applied_taxes, :count).from(0).to(1)

      expect(result).to be_success
      expect(result.applied_taxes.map(&:tax)).to eq([tax1])
    end
  end

  context "when the catalog plan already has taxes" do
    before do
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax: tax1, organization:)
      catalog_plan.taxes.load
    end

    let(:tax_codes) { [tax2.code] }

    it "replaces the existing taxes and resets the loaded association" do
      expect { result }.not_to change(catalog_plan.applied_taxes, :count)

      expect(result).to be_success
      expect(catalog_plan.taxes).to eq([tax2])
    end
  end

  context "when tax codes are empty" do
    before { create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax: tax1, organization:) }

    let(:tax_codes) { [] }

    it "removes all taxes" do
      expect { result }.to change(catalog_plan.applied_taxes, :count).from(1).to(0)

      expect(result).to be_success
      expect(result.applied_taxes).to be_empty
    end
  end

  context "when a tax code does not exist" do
    let(:tax_codes) { [tax1.code, "unknown"] }

    it "returns a tax not found failure without changing assignments" do
      expect { result }.not_to change(catalog_plan.applied_taxes, :count)

      expect(result).not_to be_success
      expect(result.error.resource).to eq("tax")
    end
  end

  context "when the tax belongs to another organization" do
    let(:other_tax) { create(:tax) }
    let(:tax_codes) { [other_tax.code] }

    it "returns a tax not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("tax")
    end
  end

  context "when the catalog plan is nil" do
    let(:catalog_plan) { nil }

    it "returns a plan not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan")
    end
  end
end
