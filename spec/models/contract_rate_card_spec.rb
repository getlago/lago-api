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
    describe ".due_for_billing" do
      let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }
      let(:organization) { create(:organization) }

      # Priced by default: an unpriced rate card is not due, which one example checks on its own.
      def card(contract: nil, priced: true, **attributes)
        contract ||= create(:contract, organization:, started_at: 1.year.ago)
        rate_card = create(:rate_card, organization:)
        create(:rate_card_rate, organization:, rate_card:) if priced

        create(:contract_rate_card, organization:, contract:, rate_card:, **attributes)
      end

      it "takes cards whose clock has come due" do
        due = card(next_billing_at: timestamp)
        overdue = card(next_billing_at: timestamp - 1.day)
        card(next_billing_at: timestamp + 1.second)

        expect(described_class.due_for_billing(timestamp)).to contain_exactly(due, overdue)
      end

      it "leaves out a card whose schedule has run out, its clock being blank" do
        card(next_billing_at: timestamp).update!(next_billing_at: nil)

        expect(described_class.due_for_billing(timestamp)).to be_empty
      end

      # Bringing a termination forward can leave a card starting after the contract ends. It
      # has no window to owe anything in, so it is not due — and the calendar is never asked
      # to build a schedule that ends before it starts.
      it "leaves out a card that starts after its contract ends" do
        ending_early = create(:contract, organization:, started_at: 1.year.ago, ended_at: 1.month.ago)
        card(contract: ending_early, next_billing_at: timestamp, effective_date: 1.week.ago.to_date)

        expect(described_class.due_for_billing(timestamp)).to be_empty
      end

      # effective_date is the customer's local day; contracts.ended_at is a UTC instant.
      # Both cards are effective Jan 1 local and their contracts end within hours of the UTC
      # midnight the naive comparison used, one on either side of it.
      context "when the customer's day is far from UTC" do
        let(:timestamp) { Time.utc(2027, 1, 1) }

        def card_ending_at(timezone, ended_at)
          customer = create(:customer, organization:, timezone:)
          contract = create(
            :contract,
            organization:,
            customer:,
            started_at: Time.utc(2026, 12, 1),
            ended_at:
          )
          card(contract:, next_billing_at: timestamp, effective_date: Date.new(2027, 1, 1))
        end

        # Local midnight is Dec 31 11:00 UTC, so the contract still has nine hours to run.
        it "keeps a card whose contract outlives its customer-local start" do
          still_open = card_ending_at("Pacific/Tongatapu", Time.utc(2026, 12, 31, 20))

          expect(described_class.due_for_billing(timestamp)).to contain_exactly(still_open)
        end

        # Local midnight is Jan 1 12:00 UTC, after the contract ended: no window at all, and
        # letting it through makes BuildScheduleService raise on ends_at before starts_at.
        it "leaves out a card whose contract ended before its customer-local start" do
          card_ending_at("Etc/GMT+12", Time.utc(2027, 1, 1, 5))

          expect(described_class.due_for_billing(timestamp)).to be_empty
        end
      end

      it "leaves out a card whose rate card has no price yet" do
        card(next_billing_at: timestamp, priced: false)

        expect(described_class.due_for_billing(timestamp)).to be_empty
      end

      # The instant governs the whole query, not only the clock: a catch-up run for a past date
      # sees the cards that were live then, and does not lose the periods they still owe.
      it "answers for the instant it is given rather than for now" do
        past = 2.months.ago
        ended_since = card(
          contract: create(:contract, organization:, started_at: 1.year.ago, ended_at: 1.month.ago),
          next_billing_at: past,
          effective_date: 1.year.ago.to_date
        )

        expect(described_class.due_for_billing(past)).to contain_exactly(ended_since)
      end

      # Deleting a customer leaves their contracts active, so without this the card stays due
      # on every tick and the producer raises RecordNotFound loading the customer back:
      # Contract#customer is with_discarded, Customer's own default scope is not.
      it "leaves out cards of a deleted customer" do
        deleted = create(:customer, organization:)
        contract = create(:contract, organization:, customer: deleted, started_at: 1.year.ago)
        card(contract:, next_billing_at: timestamp)
        deleted.discard!

        expect(described_class.due_for_billing(timestamp)).to be_empty
      end

      it "leaves out cards of contracts that are not active" do
        %w[pending terminated canceled].each do |status|
          inactive = create(:contract, organization:, status:, started_at: 1.year.ago)
          card(contract: inactive, next_billing_at: timestamp)
        end

        expect(described_class.due_for_billing(timestamp)).to be_empty
      end

      it "leaves out a card whose contract has not started yet" do
        late_contract = create(:contract, organization:, started_at: timestamp + 1.day)
        card(contract: late_contract, next_billing_at: timestamp)

        expect(described_class.due_for_billing(timestamp)).to be_empty
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

      it "allows a new row once the previous one is deleted" do
        existing = create(:contract_rate_card, deleted_at: Time.current)
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
