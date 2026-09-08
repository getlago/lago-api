# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product do
  subject(:product) { build(:product) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(product).to define_enum_for(:product_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(usage: "usage", fixed: "fixed")
    end
  end

  describe "associations" do
    it do
      expect(product).to belong_to(:organization)
      expect(product).to belong_to(:product_category).optional
      # The subject must be a fixed item: usage items validate billable_metric presence,
      # which the optional matcher would read as a non-optional association.
      expect(build(:product, :fixed, :standalone)).to belong_to(:billable_metric).optional
      expect(product).to belong_to(:add_on).optional
      expect(product).to belong_to(:charge).optional
      expect(product).to have_many(:filters).class_name("ProductFilter")
      expect(product).to have_many(:rate_cards)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "billable_metric presence" do
      it "requires a billable_metric for usage items" do
        item = build(:product, billable_metric: nil)
        item.valid?
        expect(item.errors.added?(:billable_metric, :blank)).to be(true)
      end

      it "forbids a billable_metric on fixed items" do
        item = build(:product, :fixed, billable_metric: create(:billable_metric))
        item.valid?
        expect(item.errors.added?(:billable_metric, :present)).to be(true)
      end
    end

    describe "add_on / charge exclusivity" do
      it "rejects setting both add_on and charge" do
        item = build(:product, add_on: create(:add_on), charge: create(:standard_charge))
        item.valid?
        expect(item.errors.added?(:base, :add_on_and_charge_mutually_exclusive)).to be(true)
      end
    end

    describe "code uniqueness" do
      it "rejects a duplicate code within the organization, even across product_categories" do
        organization = create(:organization)
        product_category_a = create(:product_category, organization:)
        product_category_b = create(:product_category, organization:)
        create(:product, organization:, product_category: product_category_a, code: "shared")
        duplicate = build(:product, organization:, product_category: product_category_b, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in a different organization" do
        create(:product, :standalone, code: "shared")
        item = build(:product, :standalone, code: "shared")
        item.valid?
        expect(item.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:product) { create(:product) }

    it "is false when no plan or subscription references it" do
      expect(product.attached_to_plan_or_subscription?).to be(false)
    end

    it "is true when a plan product references it" do
      rate_card = create(:rate_card, organization: product.organization, product:)
      create(:plan_rate_card, organization: product.organization, rate_card:)

      expect(product.attached_to_plan_or_subscription?).to be(true)
    end

    it "is true when a subscription product references it" do
      rate_card = create(:rate_card, organization: product.organization, product:)
      create(:contract_rate_card, organization: product.organization, rate_card:)

      expect(product.attached_to_plan_or_subscription?).to be(true)
    end
  end
end
