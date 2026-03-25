# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItem do
  subject { create(:product_item) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:item_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(usage: "usage", fixed: "fixed", subscription: "subscription")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:product)
      expect(subject).to belong_to(:add_on).optional
      expect(subject).to belong_to(:charge).optional
      expect(subject).to have_many(:filters).class_name("ProductItemFilter").dependent(:destroy)
    end

    context "with fixed type" do
      subject { build(:product_item, :fixed) }

      it { expect(subject).to belong_to(:billable_metric).optional }
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:code)
    end

    describe "code uniqueness" do
      let(:product) { create(:product) }
      let(:billable_metric) { create(:billable_metric, organization: product.organization) }
      let(:code) { Faker::Alphanumeric.alphanumeric(number: 10) }

      before { create(:product_item, product:, organization: product.organization, billable_metric:, code:) }

      it "validates uniqueness scoped to product with deleted_at" do
        product_item = build(:product_item, product:, organization: product.organization, billable_metric:, code:)
        expect(product_item).not_to be_valid
        expect(product_item.errors[:code]).to include("value_already_exist")
      end

      it "allows same code when existing record is soft deleted" do
        described_class.with_discarded.find_by(product:, code:).discard
        product_item = build(:product_item, product:, organization: product.organization, billable_metric:, code:)
        expect(product_item).to be_valid
      end
    end

    describe "billable_metric validation" do
      it "requires billable_metric for usage type" do
        product_item = build(:product_item, :usage, billable_metric: nil)
        expect(product_item).not_to be_valid
        expect(product_item.errors[:billable_metric]).to be_present
      end

      it "rejects billable_metric for fixed type" do
        product_item = build(:product_item, :fixed, billable_metric: create(:billable_metric))
        expect(product_item).not_to be_valid
        expect(product_item.errors[:billable_metric]).to be_present
      end

      it "rejects billable_metric for subscription type" do
        product_item = build(:product_item, :subscription, billable_metric: create(:billable_metric))
        expect(product_item).not_to be_valid
        expect(product_item.errors[:billable_metric]).to be_present
      end
    end

    describe "subscription type constraints" do
      it "rejects add_on for subscription type" do
        product_item = build(:product_item, :subscription, add_on: create(:add_on))
        expect(product_item).not_to be_valid
        expect(product_item.errors[:add_on]).to be_present
      end

      it "rejects charge for subscription type" do
        charge = create(:standard_charge)
        product_item = build(:product_item, :subscription, charge:)
        expect(product_item).not_to be_valid
        expect(product_item.errors[:charge]).to be_present
      end
    end

    describe "one subscription item per product" do
      it "rejects a second subscription item on the same product" do
        product = create(:product)
        create(:product_item, :subscription, product:, organization: product.organization)
        second = build(:product_item, :subscription, product:, organization: product.organization)
        expect(second).not_to be_valid
        expect(second.errors[:item_type]).to be_present
      end

      it "allows subscription items on different products" do
        create(:product_item, :subscription)
        second = build(:product_item, :subscription)
        expect(second).to be_valid
      end
    end
  end
end
