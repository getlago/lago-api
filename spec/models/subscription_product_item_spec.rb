# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionProductItem do
  subject(:subscription_product_item) { build(:subscription_product_item) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subscription_product_item).to belong_to(:organization)
      expect(subscription_product_item).to belong_to(:subscription)
      expect(subscription_product_item).to belong_to(:product_item)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:billing_anchor_date) }
    it { is_expected.to validate_presence_of(:next_billing_at) }
    it { is_expected.to validate_presence_of(:started_at) }

    describe "active uniqueness per (subscription, product_item)" do
      it "rejects a second active row for the same subscription and product item" do
        existing = create(:subscription_product_item)
        duplicate = build(
          :subscription_product_item,
          organization: existing.organization,
          subscription: existing.subscription,
          product_item: existing.product_item
        )
        duplicate.valid?
        expect(duplicate.errors.where(:product_item_id, :taken)).to be_present
      end

      it "allows a new row once the previous one has ended" do
        existing = create(:subscription_product_item, started_at: 2.days.ago, ended_at: 1.day.ago)
        replacement = build(
          :subscription_product_item,
          organization: existing.organization,
          subscription: existing.subscription,
          product_item: existing.product_item
        )
        replacement.valid?
        expect(replacement.errors.where(:product_item_id, :taken)).not_to be_present
      end
    end

    describe "started_at before ended_at" do
      it "is valid when ended_at is after started_at" do
        item = build(:subscription_product_item, started_at: 2.days.ago, ended_at: 1.day.ago)
        expect(item).to be_valid
      end

      it "is invalid when ended_at is before started_at" do
        item = build(:subscription_product_item, started_at: 1.day.ago, ended_at: 2.days.ago)
        item.valid?
        expect(item.errors.added?(:ended_at, :must_be_after_started_at)).to be(true)
      end
    end
  end
end
