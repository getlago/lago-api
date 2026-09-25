# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycle do
  subject(:billing_cycle) { build(:billing_cycle) }

  describe "associations" do
    it do
      expect(billing_cycle).to belong_to(:organization)
      expect(billing_cycle).to belong_to(:contract_rate_card)
      expect(billing_cycle).to have_many(:billing_segments)
      expect(described_class.reflect_on_association(:contract_rate_card).scope).to be_present
    end
  end

  describe "validations" do
    it do
      expect(billing_cycle).to validate_numericality_of(:cycle_index)
        .only_integer.is_greater_than_or_equal_to(0)
      expect(billing_cycle).to validate_presence_of(:started_at)
      expect(billing_cycle).to validate_presence_of(:ended_at)
      expect(billing_cycle).to validate_presence_of(:reference_started_at)
      expect(billing_cycle).to validate_presence_of(:timezone)
      expect(billing_cycle).not_to allow_value("invalid/timezone").for(:timezone)
    end

    describe "period bounds" do
      subject(:billing_cycle) do
        build(:billing_cycle, started_at:, ended_at:, reference_started_at:)
      end

      let(:started_at) { Time.utc(2026, 6, 15) }
      let(:ended_at) { Time.utc(2026, 7, 1) }
      let(:reference_started_at) { Time.utc(2026, 6, 1) }

      it "allows a stub inside the full reference period" do
        expect(billing_cycle).to be_valid
      end

      context "when the end equals the start" do
        let(:ended_at) { started_at }

        it "rejects an empty half-open interval" do
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

      context "when the reference starts after service" do
        let(:reference_started_at) { started_at + 1.day }

        it "rejects a reference that cannot contain the service period" do
          expect(billing_cycle).not_to be_valid
          expect(billing_cycle.errors[:reference_started_at]).to eq(["must be before or equal to started_at"])
        end
      end
    end

    describe "organization" do
      subject(:billing_cycle) { build(:billing_cycle, contract_rate_card:) }

      let(:contract_rate_card) { build_stubbed(:contract_rate_card) }

      it "rejects a card from a different organization" do
        expect(billing_cycle).not_to be_valid
        expect(billing_cycle.errors[:organization_id]).to eq(["must match the contract rate card's organization"])
      end
    end
  end

  describe "database constraints" do
    subject(:duplicate) do
      build(:billing_cycle, organization: existing.organization,
        contract_rate_card: existing.contract_rate_card, cycle_index:,
        started_at:, ended_at: started_at + 1.month, reference_started_at: started_at)
    end

    let!(:existing) { create(:billing_cycle, started_at: Time.utc(2026, 6, 1)) }
    let(:cycle_index) { existing.cycle_index }
    let(:started_at) { Time.utc(2026, 7, 1) }

    it "rejects reusing a cycle index for another period" do
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
