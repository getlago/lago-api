# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletAppliedTax do
  subject(:applied_tax) { build(:catalog_wallet_applied_tax) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(applied_tax).to belong_to(:organization)
      expect(applied_tax).to belong_to(:plan_wallet).optional
      expect(applied_tax).to belong_to(:catalog_wallet).optional
      expect(applied_tax).to belong_to(:tax)
    end
  end

  describe "validations" do
    it "accepts a plan wallet owner" do
      expect(build(:catalog_wallet_applied_tax, :plan_level)).to be_valid
    end

    it "rejects two owners" do
      applied_tax = build(:catalog_wallet_applied_tax, plan_wallet: create(:plan_wallet))

      expect(applied_tax.tap(&:valid?).errors).to be_added(:base, :exactly_one_owner_required)
    end
  end

  describe "database constraints" do
    it "refuses the same tax twice on a wallet" do
      existing = create(:catalog_wallet_applied_tax)
      duplicate = build(:catalog_wallet_applied_tax, catalog_wallet: existing.catalog_wallet, tax: existing.tax)

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_wallet_applied_taxes_on_catalog_wallet_and_tax/)
    end
  end
end
