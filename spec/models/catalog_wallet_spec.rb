# frozen_string_literal: true

require "rails_helper"

describe CatalogWallet do
  subject(:catalog_wallet) { build(:catalog_wallet) }

  it_behaves_like "paper_trail traceable"

  it_behaves_like "a catalog code", :catalog_wallet

  describe "enums" do
    it do
      expect(catalog_wallet).to define_enum_for(:tax_application)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(tax_on_consumption: "tax_on_consumption", tax_on_purchase: "tax_on_purchase")
    end
  end

  describe "associations" do
    it do
      expect(catalog_wallet).to belong_to(:organization)
      expect(catalog_wallet).to belong_to(:contract)
      expect(catalog_wallet).to belong_to(:customer)
      expect(catalog_wallet).to have_many(:credit_allocations).class_name("CatalogWalletCreditAllocation")
      expect(catalog_wallet).to have_many(:selectors).class_name("CatalogWalletSelector")
      expect(catalog_wallet).to have_many(:applied_taxes).class_name("CatalogWalletAppliedTax")
      expect(catalog_wallet).to have_many(:taxes).through(:applied_taxes)
      expect(catalog_wallet).to have_one(:metadata).class_name("Metadata::ItemMetadata").dependent(:destroy)
    end
  end

  describe "validations" do
    it do
      expect(catalog_wallet).to validate_presence_of(:code)
      expect(catalog_wallet).to validate_inclusion_of(:currency).in_array(described_class.currency_list)
      expect(catalog_wallet).to validate_inclusion_of(:priority).in_range(1..50)
      expect(catalog_wallet).to have_readonly_attribute(:currency)
      expect(catalog_wallet).to have_readonly_attribute(:tax_application)
    end

    describe "code uniqueness" do
      let(:existing) { create(:catalog_wallet, code: "credits") }

      it "rejects a code already kept on the contract" do
        duplicate = build(:catalog_wallet, contract: existing.contract, customer: existing.customer, code: "credits")

        expect(duplicate.tap(&:valid?).errors.where(:code, :taken)).to be_present
      end

      it "accepts the code on another contract" do
        expect(build(:catalog_wallet, organization: existing.organization, code: "credits")).to be_valid
      end
    end
  end
end
