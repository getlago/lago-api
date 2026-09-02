# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCard do
  subject(:subscription_rate_card) { build(:subscription_rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subscription_rate_card).to belong_to(:organization)
      expect(subscription_rate_card).to belong_to(:subscription)
      expect(subscription_rate_card).to belong_to(:customer)
      expect(subscription_rate_card).to belong_to(:rate_card)
      expect(subscription_rate_card).to have_many(:rate_phases).order(:position)
      expect(subscription_rate_card).to have_many(:billing_cycles)
      expect(subscription_rate_card).to have_one(:product).through(:rate_card)
    end
  end

  describe "Scopes" do
    describe ".due_for_range" do
      subject(:due_items) { described_class.due_for_range(range) }

      let(:range) { Time.zone.parse("2026-08-15 12:00:00")..Time.zone.parse("2026-08-15 12:00:00") }
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }
      let!(:due_by_next_billing_at) do
        create_item(
          started_at: Time.zone.parse("2026-08-01"),
          next_billing_at: Time.zone.parse("2026-08-15 23:00:00")
        )
      end

      before do
        create_item(
          started_at: Time.zone.parse("2026-08-01"),
          ended_at: Time.zone.parse("2026-08-15 08:00:00"),
          next_billing_at: Time.zone.parse("2026-09-01")
        )
        create_item(
          started_at: Time.zone.parse("2026-08-16"),
          next_billing_at: Time.zone.parse("2026-08-15")
        )
        create_item(
          started_at: Time.zone.parse("2026-08-01"),
          ended_at: Time.zone.parse("2026-08-14 23:59:59"),
          next_billing_at: Time.zone.parse("2026-08-15")
        )
        create_item(
          started_at: Time.zone.parse("2026-08-01"),
          next_billing_at: Time.zone.parse("2026-08-16")
        )
      end

      it "returns items active in the range with due clocks" do
        expect(due_items).to eq([due_by_next_billing_at])
      end

      def create_item(attributes)
        create(
          :subscription_rate_card,
          organization:,
          customer:,
          subscription:,
          rate_card: create(:rate_card, organization:),
          **attributes
        )
      end
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

  it_behaves_like "a rate phase parent" do
    let(:item) { create(:subscription_rate_card) }
    let(:create_rate_phase) do
      ->(attributes) { create(:rate_phase, :subscription_level, subscription_rate_card: item, **attributes) }
    end
  end
end
