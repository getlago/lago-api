# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilter do
  subject(:product_item_filter) { build(:product_item_filter) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product_item_filter).to belong_to(:organization)
      expect(product_item_filter).to belong_to(:product_item)
      expect(product_item_filter).to have_many(:values).class_name("ProductItemFilterValue")
      expect(product_item_filter).to have_many(:billable_metric_filters).through(:values)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "code uniqueness per product item" do
      it "rejects a duplicate code on the same product item" do
        existing = create(:product_item_filter)
        duplicate = build(
          :product_item_filter,
          organization: existing.organization,
          product_item: existing.product_item,
          code: existing.code
        )
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code on a different product item" do
        existing = create(:product_item_filter)
        other = build(:product_item_filter, organization: existing.organization, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#invoice_name" do
    it "returns the invoice_display_name when present" do
      filter = build_stubbed(:product_item_filter, invoice_display_name: "Display", name: "Name")
      expect(filter.invoice_name).to eq("Display")
    end

    it "falls back to name when invoice_display_name is blank" do
      filter = build_stubbed(:product_item_filter, invoice_display_name: nil, name: "Name")
      expect(filter.invoice_name).to eq("Name")
    end
  end

  describe "#to_h" do
    it "groups values by billable metric filter key" do
      filter = create(:product_item_filter)
      region = create(:billable_metric_filter, organization: filter.organization, key: "region", values: %w[us eu])
      scheme = create(:billable_metric_filter, organization: filter.organization, key: "scheme", values: %w[visa])
      create(:product_item_filter_value, product_item_filter: filter, organization: filter.organization, billable_metric_filter: region, value: "us")
      create(:product_item_filter_value, product_item_filter: filter, organization: filter.organization, billable_metric_filter: region, value: "eu")
      create(:product_item_filter_value, product_item_filter: filter, organization: filter.organization, billable_metric_filter: scheme, value: "visa")

      expect(filter.reload.to_h).to eq("region" => %w[us eu], "scheme" => %w[visa])
    end
  end
end
