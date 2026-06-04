# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItem do
  subject(:product_item) { build(:product_item) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(product_item).to define_enum_for(:item_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(usage: "usage", fixed: "fixed")
    end
  end

  describe "associations" do
    it do
      expect(product_item).to belong_to(:organization)
      expect(product_item).to belong_to(:product).optional
      expect(product_item).to belong_to(:billable_metric).optional
      expect(product_item).to belong_to(:add_on).optional
      expect(product_item).to belong_to(:charge).optional
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "billable_metric presence" do
      it "requires a billable_metric for usage items" do
        item = build(:product_item, billable_metric: nil)
        item.valid?
        expect(item.errors.added?(:billable_metric_id, :blank)).to be(true)
      end

      it "forbids a billable_metric on fixed items" do
        item = build(:product_item, :fixed, billable_metric: create(:billable_metric))
        item.valid?
        expect(item.errors.added?(:billable_metric_id, :present)).to be(true)
      end
    end

    describe "add_on / charge exclusivity" do
      it "rejects setting both add_on and charge" do
        item = build(:product_item, add_on: create(:add_on), charge: create(:standard_charge))
        item.valid?
        expect(item.errors.added?(:base, :add_on_and_charge_mutually_exclusive)).to be(true)
      end
    end

    describe "code uniqueness" do
      it "scopes uniqueness per product for product-linked items" do
        product = create(:product)
        create(:product_item, organization: product.organization, product:, code: "shared")
        duplicate = build(:product_item, organization: product.organization, product:, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code on a different product" do
        organization = create(:organization)
        product_a = create(:product, organization:)
        product_b = create(:product, organization:)
        create(:product_item, organization:, product: product_a, code: "shared")
        item = build(:product_item, organization:, product: product_b, code: "shared")
        item.valid?
        expect(item.errors.where(:code, :taken)).not_to be_present
      end

      it "scopes uniqueness per organization for standalone items" do
        organization = create(:organization)
        create(:product_item, :standalone, organization:, code: "shared")
        duplicate = build(:product_item, :standalone, organization:, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end
    end
  end
end
