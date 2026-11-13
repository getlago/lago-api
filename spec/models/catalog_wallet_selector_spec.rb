# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletSelector do
  subject(:selector) { build(:catalog_wallet_selector) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(selector).to define_enum_for(:selector_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(fee_type: "fee_type", product_category: "product_category", product: "product", product_filters: "product_filters")
        .with_prefix
      expect(selector).to define_enum_for(:fee_type)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(fixed: "fixed", metered: "metered")
        .with_prefix
    end
  end

  describe "associations" do
    it do
      expect(selector).to belong_to(:organization)
      expect(selector).to belong_to(:plan_wallet).optional
      expect(selector).to belong_to(:catalog_wallet).optional
      expect(selector).to belong_to(:product_category).optional
      expect(selector).to belong_to(:product).optional
      expect(selector).to belong_to(:product_filter).optional
    end
  end

  describe "validations" do
    it "accepts a plan wallet owner" do
      expect(build(:catalog_wallet_selector, :plan_level)).to be_valid
    end

    it "rejects a selector with no owner" do
      errors = build(:catalog_wallet_selector, catalog_wallet: nil).tap(&:valid?).errors

      expect(errors).to be_added(:base, :exactly_one_owner_required)
      expect(errors.messages[:base]).to eq(["exactly_one_owner_required"])
    end

    describe "target validation" do
      it "requires the target of the selector type" do
        selector = build(:catalog_wallet_selector, selector_type: "product", fee_type: nil)

        expect(selector.tap(&:valid?).errors.to_hash).to eq(product_id: ["value_is_mandatory"])
      end

      it "refuses the targets of other types" do
        selector = build(:catalog_wallet_selector, product_category: create(:product_category), product_filter: create(:product_filter))

        expect(selector.tap(&:valid?).errors.to_hash).to eq(
          product_category_id: ["value_must_be_blank"],
          product_filter_id: ["value_must_be_blank"]
        )
      end

      it "refuses product filters on a selector that is not a product" do
        selector = build(:catalog_wallet_selector, with_product_filters: true)

        expect(selector.tap(&:valid?).errors.to_hash).to eq(with_product_filters: ["value_must_be_blank"])
      end

      it "accepts product filters on a product selector" do
        selector = build(:catalog_wallet_selector, selector_type: "product", fee_type: nil, product: create(:product), with_product_filters: true)

        expect(selector).to be_valid
      end
    end
  end

  describe "database constraints" do
    it "refuses a target that is not the selector type's" do
      selector = build(:catalog_wallet_selector, fee_type: nil, product: create(:product))

      expect { selector.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_selectors_target_matches_type/)
    end

    it "refuses product filters on a selector that is not a product" do
      selector = build(:catalog_wallet_selector, with_product_filters: true)

      expect { selector.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_wallet_selectors_target_matches_type/)
    end

    it "refuses the same selector twice on a wallet" do
      existing = create(:catalog_wallet_selector)
      duplicate = build(:catalog_wallet_selector, catalog_wallet: existing.catalog_wallet)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
