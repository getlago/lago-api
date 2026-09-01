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
      expect(subscription_rate_card).to have_many(:billing_segments)
      expect(subscription_rate_card).to have_one(:product).through(:rate_card)
    end

    # The matcher above does not check the association's scope, and the scope is what keeps
    # the billing clock alive: Customer default-scopes to kept, so an unscoped association
    # reads a discarded customer back as nil and the clock loses its timezone.
    it "still reaches a discarded customer" do
      card = create(:subscription_rate_card)
      card.customer.discard!

      expect(card.reload.customer).to be_present
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
  # A units change versions the row instead of editing it, so the rows for one
  # (subscription, rate_card) pair are the quantity history of a single card.
  describe "#card_versions" do
    subject(:card_versions) { current.card_versions }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:rate_card) { create(:rate_card, organization:) }

    let!(:original) do
      create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:,
        started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 3, 1), units: 1)
    end
    let!(:current) do
      create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:,
        started_at: Time.utc(2026, 3, 1), units: 3)
    end

    it "returns every version of the card, oldest first" do
      expect(card_versions).to eq([original, current])
    end

    it "leaves out another card on the same subscription" do
      other = create(:subscription_rate_card, organization:, subscription:, customer:,
        started_at: Time.utc(2026, 1, 1))

      expect(card_versions).not_to include(other)
    end
  end

  describe "#card_started_at" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:rate_card) { create(:rate_card, organization:) }

    it "is the card's own start when it has never been versioned" do
      card = create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:,
        started_at: Time.utc(2026, 1, 1))

      expect(card.card_started_at).to eq(Time.utc(2026, 1, 1))
    end

    # Billing periods are anchored on the card, not on whichever version is current: using
    # this version's start would clip every period to the moment the quantity last moved.
    it "reaches back to the first version when the quantity has changed" do
      create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:,
        started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 3, 1))
      current = create(:subscription_rate_card, organization:, subscription:, customer:, rate_card:,
        started_at: Time.utc(2026, 3, 1))

      expect(current.card_started_at).to eq(Time.utc(2026, 1, 1))
    end
  end
end
