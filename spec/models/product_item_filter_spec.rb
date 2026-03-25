# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilter do
  subject { create(:product_item_filter) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:product_item)
      expect(subject).to belong_to(:billable_metric_filter)
      expect(subject).to have_many(:values).class_name("ProductItemFilterValue").dependent(:destroy)
    end
  end

  describe "validations" do
    describe "billable_metric_filter_id uniqueness" do
      it "validates uniqueness scoped to product_item with deleted_at" do
        duplicate = build(:product_item_filter,
          product_item: subject.product_item,
          billable_metric_filter: subject.billable_metric_filter,
          organization: subject.organization)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:billable_metric_filter_id]).to include("value_already_exist")
      end

      it "allows same filter when existing record is soft deleted" do
        product_item = subject.product_item
        bmf = subject.billable_metric_filter
        subject.discard
        duplicate = build(:product_item_filter, product_item:, billable_metric_filter: bmf, organization: subject.organization)
        expect(duplicate).to be_valid
      end
    end
  end
end
