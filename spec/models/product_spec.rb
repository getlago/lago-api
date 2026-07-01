# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product do
  subject(:product) { build(:product) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product).to belong_to(:organization)
      expect(product).to have_many(:product_items)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "code uniqueness" do
      it "does not add an error when unique within the organization" do
        expect(product.tap(&:valid?).errors.where(:code, :taken)).not_to be_present
      end

      it "adds an error when not unique within the organization" do
        organization = create(:organization)
        create(:product, organization:, code: "shared")
        duplicate = build(:product, organization:, code: "shared")
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code across organizations" do
        create(:product, code: "shared")
        other = build(:product, organization: create(:organization), code: "shared")
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#invoice_name" do
    it "returns the invoice_display_name when present" do
      product = build_stubbed(:product, invoice_display_name: "Display", name: "Name")
      expect(product.invoice_name).to eq("Display")
    end

    it "falls back to name when invoice_display_name is blank" do
      product = build_stubbed(:product, invoice_display_name: nil, name: "Name")
      expect(product.invoice_name).to eq("Name")
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:product) { create(:product) }

    it "is false when the product is not in a plan and none of its items has a subscription" do
      create(:product_item, organization: product.organization, product:)

      expect(product.attached_to_plan_or_subscription?).to be(false)
    end

    it "is true when the product is attached to a plan" do
      create(:plan_product, organization: product.organization, product:)

      expect(product.attached_to_plan_or_subscription?).to be(true)
    end

    it "is true when one of its items has a subscription product item" do
      item = create(:product_item, organization: product.organization, product:)
      create(:subscription_product_item, organization: product.organization, product_item: item)

      expect(product.attached_to_plan_or_subscription?).to be(true)
    end
  end
end
