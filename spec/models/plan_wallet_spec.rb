# frozen_string_literal: true

require "rails_helper"

describe PlanWallet do
  subject(:plan_wallet) { build(:plan_wallet) }

  it_behaves_like "paper_trail traceable"

  it_behaves_like "a catalog code", :plan_wallet

  describe "enums" do
    it do
      expect(plan_wallet).to define_enum_for(:tax_application)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(tax_on_consumption: "tax_on_consumption", tax_on_purchase: "tax_on_purchase")
    end
  end

  describe "associations" do
    it do
      expect(plan_wallet).to belong_to(:organization)
      expect(plan_wallet).to belong_to(:catalog_plan)
      expect(plan_wallet).to have_many(:credit_allocations).class_name("PlanWalletCreditAllocation")
      expect(plan_wallet).to have_many(:selectors).class_name("CatalogWalletSelector")
      expect(plan_wallet).to have_many(:applied_taxes).class_name("CatalogWalletAppliedTax")
      expect(plan_wallet).to have_many(:taxes).through(:applied_taxes)
      expect(plan_wallet).to have_one(:metadata).class_name("Metadata::ItemMetadata").dependent(:destroy)
    end
  end

  describe "validations" do
    it do
      expect(plan_wallet).to validate_presence_of(:code)
      expect(plan_wallet).to validate_inclusion_of(:currency).in_array(described_class.currency_list)
      expect(plan_wallet).to validate_inclusion_of(:priority).in_range(1..50)
      expect(plan_wallet).to validate_numericality_of(:top_up_min_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil
      expect(plan_wallet).to validate_numericality_of(:top_up_max_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil
    end

    describe "code uniqueness" do
      let(:existing) { create(:plan_wallet, code: "credits") }

      it "rejects a code already kept on the plan" do
        duplicate = build(:plan_wallet, catalog_plan: existing.catalog_plan, organization: existing.organization, code: "credits")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      context "when the wallet holding the code is discarded" do
        let(:existing) { create(:plan_wallet, code: "credits", deleted_at: Time.current) }

        it "accepts the code" do
          reused = build(:plan_wallet, catalog_plan: existing.catalog_plan, organization: existing.organization, code: "credits")

          expect(reused).to be_valid
        end
      end
    end

    describe "top-up limits" do
      it "accepts equal limits" do
        expect(build(:plan_wallet, top_up_min_amount_cents: 1000, top_up_max_amount_cents: 1000)).to be_valid
      end

      it "rejects a maximum below the minimum" do
        wallet = build(:plan_wallet, top_up_min_amount_cents: 1000, top_up_max_amount_cents: 999)

        expect(wallet).not_to be_valid
        expect(wallet.errors.where(:top_up_max_amount_cents, :greater_than_or_equal_to)).to be_present
      end
    end
  end
end
