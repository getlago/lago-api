# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProduct do
  subject { create(:plan_product) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:plan)
      expect(subject).to belong_to(:product)
    end
  end

  describe "validations" do
    describe "product_id uniqueness" do
      it "validates uniqueness scoped to plan with deleted_at" do
        duplicate = build(:plan_product, plan: subject.plan, product: subject.product, organization: subject.organization)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:product_id]).to include("value_already_exist")
      end

      it "allows same product when existing record is soft deleted" do
        plan = subject.plan
        product = subject.product
        subject.discard
        duplicate = build(:plan_product, plan:, product:, organization: subject.organization)
        expect(duplicate).to be_valid
      end
    end
  end
end
