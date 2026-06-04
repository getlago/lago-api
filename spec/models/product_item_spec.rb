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
      # The subject must be a fixed item: usage items validate billable_metric presence,
      # which the optional matcher would read as a non-optional association.
      expect(build(:product_item, :fixed, :standalone)).to belong_to(:billable_metric).optional
      expect(product_item).to belong_to(:add_on).optional
      expect(product_item).to belong_to(:charge).optional
      expect(product_item).to have_many(:filters).class_name("ProductItemFilter")
      expect(product_item).to have_many(:rate_cards)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "billable_metric presence" do
      it "requires a billable_metric for usage items" do
        item = build(:product_item, billable_metric: nil)
        item.valid?
        expect(item.errors.added?(:billable_metric, :blank)).to be(true)
      end

      it "forbids a billable_metric on fixed items" do
        item = build(:product_item, :fixed, billable_metric: create(:billable_metric))
        item.valid?
        expect(item.errors.added?(:billable_metric, :present)).to be(true)
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
      it "rejects a duplicate code within the organization, even across products" do
        organization = create(:organization)
        product_a = create(:product, organization:)
        product_b = create(:product, organization:)
        create(:product_item, organization:, product: product_a, code: "shared")
        duplicate = build(:product_item, organization:, product: product_b, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in a different organization" do
        create(:product_item, :standalone, code: "shared")
        item = build(:product_item, :standalone, code: "shared")
        item.valid?
        expect(item.errors.where(:code, :taken)).not_to be_present
      end
    end
  end
end
