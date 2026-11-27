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
      expect(catalog_wallet).to have_many(:transactions).class_name("CatalogWalletTransaction").inverse_of(:catalog_wallet)
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

      context "when the code of a deleted wallet is in use again" do
        let(:deleted) { create(:catalog_wallet, code: "credits", deleted_at: 1.day.ago) }

        before { create(:catalog_wallet, contract: deleted.contract, customer: deleted.customer, code: "credits") }

        it "accepts the deleted wallet" do
          expect(deleted).to be_valid
        end
      end
    end

    describe "currency validation" do
      subject(:catalog_wallet) { build(:catalog_wallet, contract:, customer:, currency:) }

      let(:customer) { create(:customer, currency: "USD") }
      let(:contract) { create(:contract, customer:) }
      let(:currency) { "USD" }

      it "accepts the currency of the contract" do
        expect(catalog_wallet).to be_valid
      end

      context "with another currency" do
        let(:currency) { "EUR" }

        it "rejects it" do
          expect(catalog_wallet).not_to be_valid
          expect(catalog_wallet.errors.where(:currency, :currency_does_not_match)).to be_present
        end
      end

      context "with an unknown currency" do
        let(:currency) { "XXX" }

        it "only reports the unknown currency" do
          expect(catalog_wallet).not_to be_valid
          expect(catalog_wallet.errors.details[:currency].map { it[:error] }).to eq([:inclusion])
        end
      end

      context "when the contract has a plan in another currency than its customer" do
        let(:contract) { create(:contract, customer:, catalog_plan: create(:catalog_plan, currency: "EUR")) }

        it "rejects the currency of the customer" do
          expect(catalog_wallet).not_to be_valid
          expect(catalog_wallet.errors.where(:currency, :currency_does_not_match)).to be_present
        end

        context "with the currency of the plan" do
          let(:currency) { "EUR" }

          it "accepts it" do
            expect(catalog_wallet).to be_valid
          end
        end
      end

      context "when a saved wallet no longer has the currency of its contract" do
        let(:currency) { "EUR" }

        before { catalog_wallet.save!(validate: false) }

        it "accepts other changes" do
          expect(catalog_wallet.update(name: "Renamed")).to be(true)
        end
      end
    end
  end

  describe "#funded?" do
    it "is true once the wallet holds money" do
      expect(build(:catalog_wallet, balance_cents: 1).funded?).to be(true)
    end

    it "is false on an empty wallet" do
      expect(build(:catalog_wallet, balance_cents: 0).funded?).to be(false)
    end
  end
end
