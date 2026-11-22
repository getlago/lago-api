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
      expect(catalog_wallet).to have_many(:transactions).class_name("CatalogWalletTransaction")
      expect(catalog_wallet).to have_many(:alerts).class_name("UsageMonitoring::CatalogWalletAlert").dependent(:delete_all).inverse_of(:catalog_wallet)
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
      expect(catalog_wallet).to validate_numericality_of(:priority).only_integer.is_greater_than_or_equal_to(1).is_less_than_or_equal_to(50)
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

  describe "#alerts_read_only?" do
    subject(:catalog_wallet) { build(:catalog_wallet, contract:, terminated_at:) }

    let(:contract) { build(:contract) }
    let(:terminated_at) { nil }

    it "is false while the wallet and its contract are live" do
      expect(catalog_wallet.alerts_read_only?).to be(false)
    end

    context "when the contract is pending" do
      let(:contract) { build(:contract, :pending) }

      it { expect(catalog_wallet.alerts_read_only?).to be(false) }
    end

    %i[terminated canceled].each do |status|
      context "when the contract is #{status}" do
        let(:contract) { build(:contract, status) }

        it { expect(catalog_wallet.alerts_read_only?).to be(true) }
      end
    end

    context "when the wallet has ended" do
      let(:terminated_at) { Time.current }

      it { expect(catalog_wallet.alerts_read_only?).to be(true) }
    end
  end
end
