# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategory do
  subject(:product_category) { build(:product_category) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product_category).to belong_to(:organization)
      expect(product_category).to have_many(:products)
      expect(product_category).to have_many(:contract_applied_rate_cards).through(:products)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "code uniqueness" do
      it "does not add an error when unique within the organization" do
        expect(product_category.tap(&:valid?).errors.where(:code, :taken)).not_to be_present
      end

      it "adds an error when not unique within the organization" do
        organization = create(:organization)
        create(:product_category, organization:, code: "shared")
        duplicate = build(:product_category, organization:, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code across organizations" do
        create(:product_category, code: "shared")
        other = build(:product_category, organization: create(:organization), code: "shared")
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#invoice_name" do
    it "returns the invoice_display_name when present" do
      product_category = build_stubbed(:product_category, invoice_display_name: "Display", name: "Name")
      expect(product_category.invoice_name).to eq("Display")
    end

    it "falls back to name when invoice_display_name is blank" do
      product_category = build_stubbed(:product_category, invoice_display_name: nil, name: "Name")
      expect(product_category.invoice_name).to eq("Name")
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:product_category) { create(:product_category) }

    it "is false when the product_category is not in a plan and none of its items has a subscription" do
      create(:product, organization: product_category.organization, product_category:)

      expect(product_category.attached_to_plan_or_subscription?).to be(false)
    end

    it "is true when one of its items is priced on a plan" do
      item = create(:product, organization: product_category.organization, product_category:)
      rate_card = create(:rate_card, organization: product_category.organization, product: item)
      create(:plan_rate_card, organization: product_category.organization, rate_card:)

      expect(product_category.attached_to_plan_or_subscription?).to be(true)
    end

    it "is true when one of its items has a subscription product" do
      item = create(:product, organization: product_category.organization, product_category:)
      rate_card = create(:rate_card, organization: product_category.organization, product: item)
      create(:contract_rate_card, organization: product_category.organization, rate_card:)

      expect(product_category.attached_to_plan_or_subscription?).to be(true)
    end
  end
end
