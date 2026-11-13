# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletCreditAllocation do
  subject(:allocation) { build(:catalog_wallet_credit_allocation) }

  it_behaves_like "paper_trail traceable"

  it_behaves_like "a catalog code", :catalog_wallet_credit_allocation

  describe "enums" do
    it do
      expect(allocation).to define_enum_for(:trigger)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(billing_cycle: "billing_cycle", ongoing_balance: "ongoing_balance")
    end
  end

  describe "associations" do
    it do
      expect(allocation).to belong_to(:organization)
      expect(allocation).to belong_to(:catalog_wallet)
      expect(allocation).to have_many(:transactions).class_name("CatalogWalletTransaction").with_foreign_key(:credit_allocation_id).inverse_of(:credit_allocation)
      expect(allocation).to belong_to(:product).optional
      expect(allocation).to belong_to(:product_filter).optional
    end
  end

  describe "validations" do
    it do
      expect(allocation).to validate_presence_of(:code)
      expect(allocation).to validate_numericality_of(:credit_amount_cents).only_integer.is_greater_than(0)
      expect(allocation).to validate_inclusion_of(:priority).in_range(1..50)
      expect(allocation).to validate_numericality_of(:billing_cycles).only_integer.is_greater_than(0).allow_nil
      expect(allocation).to validate_numericality_of(:threshold_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil
      expect(allocation).to validate_numericality_of(:purchase_amount_cents).only_integer.is_greater_than_or_equal_to(0).allow_nil
      expect(build(:catalog_wallet_credit_allocation, :ongoing_balance)).to be_valid
    end

    describe "code uniqueness" do
      let(:existing) { create(:catalog_wallet_credit_allocation, code: "allowance") }

      it "rejects a code already kept on the wallet" do
        duplicate = build(:catalog_wallet_credit_allocation, catalog_wallet: existing.catalog_wallet, code: "allowance")

        expect(duplicate.tap(&:valid?).errors.where(:code, :taken)).to be_present
      end
    end

    describe "billing cycle source" do
      it "rejects a rule with no source" do
        expect(build(:catalog_wallet_credit_allocation, product: nil).tap(&:valid?).errors)
          .to be_added(:base, :exactly_one_source_required)
      end

      it "rejects a rule with two sources" do
        expect(build(:catalog_wallet_credit_allocation, product_filter: create(:product_filter)).tap(&:valid?).errors)
          .to be_added(:base, :exactly_one_source_required)
      end
    end

    describe "ongoing balance fields" do
      it "requires them on an ongoing balance rule" do
        rule = build(
          :catalog_wallet_credit_allocation,
          :ongoing_balance,
          threshold_amount_cents: nil,
          purchase_amount_cents: nil,
          invoice_requires_successful_payment: nil
        )

        expect(rule.tap(&:valid?).errors.to_hash).to eq(
          threshold_amount_cents: ["value_is_mandatory"],
          purchase_amount_cents: ["value_is_mandatory"],
          invoice_requires_successful_payment: ["value_is_invalid"]
        )
      end

      it "refuses them on a billing cycle rule" do
        rule = build(
          :catalog_wallet_credit_allocation,
          threshold_amount_cents: 0,
          purchase_amount_cents: 0,
          invoice_requires_successful_payment: false
        )

        expect(rule.tap(&:valid?).errors.to_hash).to eq(
          threshold_amount_cents: ["value_must_be_blank"],
          purchase_amount_cents: ["value_must_be_blank"],
          invoice_requires_successful_payment: ["value_must_be_blank"]
        )
      end
    end

    describe "billing cycle fields" do
      it "refuses them on an ongoing balance rule" do
        rule = build(
          :catalog_wallet_credit_allocation,
          :ongoing_balance,
          product: create(:product),
          product_filter: create(:product_filter),
          billing_cycles: 3
        )

        expect(rule.tap(&:valid?).errors.to_hash).to eq(
          product: ["value_must_be_blank"],
          product_filter: ["value_must_be_blank"],
          billing_cycles: ["value_must_be_blank"]
        )
      end
    end
  end

  describe "database constraints" do
    it "refuses a rule capped at zero billing cycles" do
      rule = build(:catalog_wallet_credit_allocation, billing_cycles: 0)

      expect { rule.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_credit_allocations_billing_cycles_positive/)
    end

    it "refuses a rule that adds no credit" do
      rule = build(:catalog_wallet_credit_allocation, credit_amount_cents: 0)

      expect { rule.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_credit_allocations_credit_amount_positive/)
    end

    it "refuses a billing cycle rule with a threshold" do
      rule = build(:catalog_wallet_credit_allocation, threshold_amount_cents: 0)

      expect { rule.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_credit_allocations_trigger_fields/)
    end

    it "refuses an ongoing balance rule with a product" do
      rule = build(:catalog_wallet_credit_allocation, :ongoing_balance, product: create(:product))

      expect { rule.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_credit_allocations_trigger_fields/)
    end

    it "refuses a second kept ongoing balance rule on the wallet" do
      existing = create(:catalog_wallet_credit_allocation, :ongoing_balance)
      second = build(:catalog_wallet_credit_allocation, :ongoing_balance, catalog_wallet: existing.catalog_wallet)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
