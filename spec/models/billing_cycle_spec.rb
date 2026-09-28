# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycle do
  subject(:billing_cycle) { build(:billing_cycle) }

  describe "associations" do
    it do
      expect(billing_cycle).to belong_to(:organization)
      expect(billing_cycle).to belong_to(:contract_rate_card)
      expect(described_class.reflect_on_association(:contract_rate_card).scope).to be_present
    end
  end

  describe "validations" do
    it do
      expect(billing_cycle).to validate_numericality_of(:cycle_index).only_integer.is_greater_than_or_equal_to(0)
      expect(billing_cycle).to validate_presence_of(:started_at)
      expect(billing_cycle).to validate_presence_of(:ended_at)
      expect(billing_cycle).to validate_presence_of(:timezone)
      expect(billing_cycle).not_to allow_value("invalid/timezone").for(:timezone)
    end

    describe "period bounds" do
      subject(:billing_cycle) { build(:billing_cycle, started_at:, ended_at:) }

      let(:started_at) { Time.utc(2026, 1, 1) }
      let(:ended_at) { Time.utc(2026, 2, 1) }

      it "accepts a nonempty half-open interval" do
        expect(billing_cycle).to be_valid
      end

      context "when the end equals the start" do
        let(:ended_at) { started_at }

        it "rejects an empty period" do
          expect(billing_cycle).not_to be_valid
          expect(billing_cycle.errors[:ended_at]).to eq(["must be after started_at (the end is exclusive)"])
        end
      end

      context "when the end precedes the start" do
        let(:ended_at) { started_at - 1.day }

        it "rejects reversed bounds" do
          expect(billing_cycle).not_to be_valid
          expect(billing_cycle.errors[:ended_at]).to eq(["must be after started_at (the end is exclusive)"])
        end
      end
    end

    describe "organization" do
      subject(:billing_cycle) { build(:billing_cycle, contract_rate_card:) }

      let(:contract_rate_card) { build_stubbed(:contract_rate_card) }

      it "rejects a card from another organization" do
        expect(billing_cycle).not_to be_valid
        expect(billing_cycle.errors[:organization_id]).to eq(["must match the contract rate card's organization"])
      end
    end
  end

  describe "historical association" do
    subject(:billing_cycle) { create(:billing_cycle, organization: contract_rate_card.organization, contract_rate_card:) }

    let(:contract_rate_card) { create(:contract_rate_card, deleted_at: Time.current) }

    it "resolves a discarded card" do
      expect(billing_cycle.reload.contract_rate_card).to eq(contract_rate_card)
    end
  end

  describe "database constraints" do
    subject(:duplicate) do
      build(:billing_cycle, organization: existing.organization, contract_rate_card: existing.contract_rate_card,
        cycle_index:, started_at:, ended_at: started_at + 1.month)
    end

    let!(:existing) { create(:billing_cycle) }
    let(:cycle_index) { existing.cycle_index }
    let(:started_at) { existing.ended_at }

    it "rejects a duplicate index on the same card" do
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    context "with another index for the same start" do
      let(:cycle_index) { existing.cycle_index + 1 }
      let(:started_at) { existing.started_at }

      it "rejects duplicating the period" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end
end
