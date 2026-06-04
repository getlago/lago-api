# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilterValue do
  subject(:product_item_filter_value) { build(:product_item_filter_value) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(product_item_filter_value).to belong_to(:organization)
      expect(product_item_filter_value).to belong_to(:product_item_filter)
      expect(product_item_filter_value).to belong_to(:billable_metric_filter)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:value) }

    describe "value inclusion in the billable metric filter values" do
      it "is valid when the value belongs to the metric filter values" do
        expect(product_item_filter_value).to be_valid
      end

      it "is invalid when the value is not in the metric filter values" do
        product_item_filter_value.value = "not-a-known-value"
        product_item_filter_value.valid?
        expect(product_item_filter_value.errors.added?(:value, :inclusion)).to be(true)
      end
    end

    describe "value uniqueness per filter and metric filter" do
      it "rejects the same value twice for the same filter and key" do
        existing = create(:product_item_filter_value)
        duplicate = build(
          :product_item_filter_value,
          organization: existing.organization,
          product_item_filter: existing.product_item_filter,
          billable_metric_filter: existing.billable_metric_filter,
          value: existing.value
        )
        duplicate.valid?
        expect(duplicate.errors.where(:value, :taken)).to be_present
      end

      it "allows the same value for a different key on the same filter" do
        existing = create(:product_item_filter_value)
        other_key = create(:billable_metric_filter, organization: existing.organization, values: [existing.value])
        sibling = build(
          :product_item_filter_value,
          organization: existing.organization,
          product_item_filter: existing.product_item_filter,
          billable_metric_filter: other_key,
          value: existing.value
        )
        sibling.valid?
        expect(sibling.errors.where(:value, :taken)).not_to be_present
      end
    end
  end

  describe "#key" do
    it "delegates to the billable metric filter" do
      expect(product_item_filter_value.key).to eq(product_item_filter_value.billable_metric_filter.key)
    end
  end
end
