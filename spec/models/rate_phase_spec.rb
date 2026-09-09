# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhase do
  subject(:rate_phase) { build(:rate_phase) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(rate_phase).to belong_to(:organization)
      expect(rate_phase).to belong_to(:plan_rate_card).optional
      expect(rate_phase).to belong_to(:contract_rate_card).optional
      expect(rate_phase).to belong_to(:rate_override).optional
    end
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:billing_interval_cycle_count).is_greater_than(0).allow_nil }

    it "rejects two kept phases sharing the same rate_override" do
      override = create(:rate_override)
      phase = create(:rate_phase, organization: override.organization, rate_override: override)
      duplicate = build(
        :rate_phase,
        organization: override.organization,
        plan_rate_card: phase.plan_rate_card,
        position: 2,
        code: "other",
        rate_override: override
      )
      duplicate.valid?

      expect(duplicate.errors.where(:rate_override_id, :taken)).to be_present
    end

    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).is_greater_than(0) }

    describe "code" do
      it { is_expected.to validate_presence_of(:code) }

      it "rejects a duplicate code on the same parent" do
        phase = create(:rate_phase, code: "launch")
        duplicate = build(
          :rate_phase,
          plan_rate_card: phase.plan_rate_card,
          organization: phase.organization,
          position: 2,
          code: "launch"
        )
        duplicate.valid?

        expect(duplicate.errors.where(:code, :taken)).to be_present
      end
    end

    describe "exactly one parent" do
      it "is valid with only a plan_rate_card" do
        expect(build(:rate_phase)).to be_valid
      end

      it "is valid with only a contract_rate_card" do
        expect(build(:rate_phase, :contract_level)).to be_valid
      end

      it "is invalid with neither parent" do
        phase = build(:rate_phase, plan_rate_card: nil, contract_rate_card: nil)
        phase.valid?
        expect(phase.errors.added?(:base, :exactly_one_parent_required)).to be(true)
      end

      it "is invalid with both parents" do
        phase = build(
          :rate_phase,
          plan_rate_card: create(:plan_rate_card),
          contract_rate_card: create(:contract_rate_card)
        )
        phase.valid?
        expect(phase.errors.added?(:base, :exactly_one_parent_required)).to be(true)
      end
    end
  end
end
