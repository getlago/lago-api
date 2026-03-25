# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProductItem do
  subject { create(:plan_product_item) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:plan)
      expect(subject).to belong_to(:product_item)
      expect(subject).to have_many(:rate_schedules)
    end
  end

  describe "validations" do
    describe "product_item_id uniqueness" do
      it "validates uniqueness scoped to plan with deleted_at" do
        duplicate = build(:plan_product_item,
          plan: subject.plan,
          product_item: subject.product_item,
          organization: subject.organization)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:product_item_id]).to include("value_already_exist")
      end

      it "allows same product_item when existing record is soft deleted" do
        plan = subject.plan
        product_item = subject.product_item
        subject.discard
        duplicate = build(:plan_product_item, plan:, product_item:, organization: subject.organization)
        expect(duplicate).to be_valid
      end
    end
  end
end
