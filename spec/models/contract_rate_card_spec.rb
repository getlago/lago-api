# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCard do
  subject(:contract_rate_card) { build(:contract_rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(contract_rate_card).to belong_to(:organization)
      expect(contract_rate_card).to belong_to(:contract)
      expect(contract_rate_card).to belong_to(:rate_card)
      expect(contract_rate_card).to have_many(:rate_phases).order(:position)
      expect(contract_rate_card).to have_many(:billing_segments)
      expect(contract_rate_card).to have_one(:product).through(:rate_card)
    end
  end

  describe "Scopes" do
    describe ".current_and_scheduled" do
      it "keeps open and upcoming attachments, hides ended ones" do
        open_card = create(:contract_rate_card)
        ending_today = create(:contract_rate_card, effective_date: 10.days.ago.to_date, ended_date: Date.current)
        create(:contract_rate_card, effective_date: 10.days.ago.to_date, ended_date: 1.day.ago.to_date)

        expect(described_class.current_and_scheduled).to contain_exactly(open_card, ending_today)
      end

      it "cuts off on the customer's day, not the application's" do
        travel_to(Time.zone.parse("2026-10-01T02:00:00Z")) do
          la_customer = create(:customer, timezone: "America/Los_Angeles")
          la_contract = create(:contract, organization: la_customer.organization, customer: la_customer)
          still_current = create(
            :contract_rate_card,
            organization: la_customer.organization,
            contract: la_contract,
            effective_date: Date.new(2026, 9, 1),
            ended_date: Date.new(2026, 9, 30)
          )

          utc_customer = create(:customer, timezone: "UTC")
          utc_contract = create(:contract, organization: utc_customer.organization, customer: utc_customer)
          create(
            :contract_rate_card,
            organization: utc_customer.organization,
            contract: utc_contract,
            effective_date: Date.new(2026, 9, 1),
            ended_date: Date.new(2026, 9, 30)
          )

          expect(described_class.current_and_scheduled).to contain_exactly(still_current)
        end
      end
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:billing_anchor_date) }
    it { is_expected.to validate_presence_of(:next_billing_at) }
    it { is_expected.to validate_presence_of(:effective_date) }
    it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0).allow_nil }

    describe "active uniqueness per (contract, rate_card)" do
      it "rejects a second active row for the same contract and rate card" do
        existing = create(:contract_rate_card)
        duplicate = build(
          :contract_rate_card,
          organization: existing.organization,
          contract: existing.contract,
          rate_card: existing.rate_card
        )
        duplicate.valid?
        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end

      it "allows a new row once the previous one has ended" do
        existing = create(:contract_rate_card, effective_date: 2.days.ago.to_date, ended_date: 1.day.ago.to_date)
        replacement = build(
          :contract_rate_card,
          organization: existing.organization,
          contract: existing.contract,
          rate_card: existing.rate_card
        )
        replacement.valid?
        expect(replacement.errors.where(:rate_card_id, :taken)).not_to be_present
      end
    end

    describe "effective_date before ended_date" do
      it "is valid when ended_date is after effective_date" do
        item = build(:contract_rate_card, effective_date: 2.days.ago.to_date, ended_date: 1.day.ago.to_date)
        expect(item).to be_valid
      end

      it "is invalid when ended_date is before effective_date" do
        item = build(:contract_rate_card, effective_date: 1.day.ago.to_date, ended_date: 2.days.ago.to_date)
        item.valid?
        expect(item.errors.added?(:ended_date, :must_be_after_effective_date)).to be(true)
      end
    end
  end

  describe "#edit_error_code" do
    it "is nil while the contract is pending" do
      card = create(:contract_rate_card, contract: create(:contract, :pending))
      expect(card.edit_error_code).to be_nil
    end

    it "is contract_locked once the contract is active" do
      card = create(:contract_rate_card, contract: create(:contract))
      expect(card.edit_error_code).to eq("contract_locked")
    end
  end
end
