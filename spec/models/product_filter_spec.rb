# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFilter do
  subject(:product_filter) { build(:product_filter) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product_filter).to belong_to(:organization)
      expect(product_filter).to belong_to(:product)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "code uniqueness per product" do
      it "rejects a duplicate code on the same product" do
        existing = create(:product_filter)
        duplicate = build(
          :product_filter,
          organization: existing.organization,
          product: existing.product,
          code: existing.code
        )
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code on a different product" do
        existing = create(:product_filter)
        other = build(:product_filter, organization: existing.organization, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#invoice_name" do
    it "returns the invoice_display_name when present" do
      filter = build_stubbed(:product_filter, invoice_display_name: "Display", name: "Name")
      expect(filter.invoice_name).to eq("Display")
    end

    it "falls back to name when invoice_display_name is blank" do
      filter = build_stubbed(:product_filter, invoice_display_name: nil, name: "Name")
      expect(filter.invoice_name).to eq("Name")
    end
  end
end
