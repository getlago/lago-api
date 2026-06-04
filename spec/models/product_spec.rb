# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product do
  subject(:product) { build(:product) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product).to belong_to(:organization)
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
end
