# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilterValue do
  subject { create(:product_item_filter_value) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:product_item_filter)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:value)
    end

    describe "value uniqueness" do
      it "validates uniqueness scoped to product_item_filter with deleted_at" do
        duplicate = build(:product_item_filter_value,
          product_item_filter: subject.product_item_filter,
          value: subject.value,
          organization: subject.organization)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:value]).to include("value_already_exist")
      end
    end

    describe "value inclusion" do
      it "rejects values not in billable_metric_filter.values" do
        filter_value = build(:product_item_filter_value,
          product_item_filter: subject.product_item_filter,
          value: "nonexistent_value_#{SecureRandom.hex}")
        expect(filter_value).not_to be_valid
        expect(filter_value.errors[:value]).to be_present
      end

      it "accepts values present in billable_metric_filter.values" do
        valid_value = subject.product_item_filter.billable_metric_filter.values.last
        filter_value = build(:product_item_filter_value,
          product_item_filter: subject.product_item_filter,
          organization: subject.organization,
          value: valid_value)
        expect(filter_value).to be_valid
      end
    end
  end
end
