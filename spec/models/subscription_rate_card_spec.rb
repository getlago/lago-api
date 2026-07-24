# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCard do
  subject(:subscription_rate_card) { build(:subscription_rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subscription_rate_card).to belong_to(:organization)
      expect(subscription_rate_card).to belong_to(:subscription)
      expect(subscription_rate_card).to belong_to(:rate_card)
      expect(subscription_rate_card).to have_one(:product_item).through(:rate_card)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:billing_anchor_date) }
    it { is_expected.to validate_presence_of(:next_billing_at) }
    it { is_expected.to validate_presence_of(:started_at) }

    describe "active uniqueness per (subscription, rate_card)" do
      it "rejects a second active row for the same subscription and rate card" do
        existing = create(:subscription_rate_card)
        duplicate = build(
          :subscription_rate_card,
          organization: existing.organization,
          subscription: existing.subscription,
          rate_card: existing.rate_card
        )
        duplicate.valid?
        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end

      it "allows a new row once the previous one has ended" do
        existing = create(:subscription_rate_card, started_at: 2.days.ago, ended_at: 1.day.ago)
        replacement = build(
          :subscription_rate_card,
          organization: existing.organization,
          subscription: existing.subscription,
          rate_card: existing.rate_card
        )
        replacement.valid?
        expect(replacement.errors.where(:rate_card_id, :taken)).not_to be_present
      end
    end

    describe "started_at before ended_at" do
      it "is valid when ended_at is after started_at" do
        item = build(:subscription_rate_card, started_at: 2.days.ago, ended_at: 1.day.ago)
        expect(item).to be_valid
      end

      it "is invalid when ended_at is before started_at" do
        item = build(:subscription_rate_card, started_at: 1.day.ago, ended_at: 2.days.ago)
        item.valid?
        expect(item.errors.added?(:ended_at, :must_be_after_started_at)).to be(true)
      end
    end
  end
end
