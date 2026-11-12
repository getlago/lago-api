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
      expect(contract_rate_card).to have_many(:terms).order([:effective_date, :created_at, :id]).class_name("ContractRateCardTerm").inverse_of(:contract_rate_card)
      expect(contract_rate_card).to have_many(:rate_phases).order(:position)
      expect(contract_rate_card).to have_many(:billing_operations)
      expect(contract_rate_card).to have_many(:fees)
      expect(contract_rate_card).to have_one(:product).through(:rate_card)
    end
  end

  describe "Scopes" do
    describe ".priced" do
      let(:organization) { create(:organization) }

      it "takes the cards whose rate card has a rate" do
        priced = create(:contract_rate_card, organization:, rate_card: create(:rate_card_rate, organization:).rate_card)
        create(:contract_rate_card, organization:)

        expect(described_class.priced).to contain_exactly(priced)
      end
    end

    describe ".starting_before_contract_end" do
      let(:organization) { create(:organization) }
      let(:contract) { create(:contract, organization:, started_at: Time.utc(2026, 1, 1), ended_at:, terminated_at:) }
      let(:ended_at) { nil }
      let(:terminated_at) { nil }
      let(:card) { create(:contract_rate_card, organization:, contract:, effective_date: Date.new(2026, 3, 1)) }

      before { card }

      it "takes a card whose contract has no end" do
        expect(described_class.starting_before_contract_end).to eq([card])
      end

      context "when the contract is terminated on the card's first day" do
        let(:terminated_at) { Time.utc(2026, 3, 1, 14) }

        it "takes the card" do
          expect(described_class.starting_before_contract_end).to eq([card])
        end
      end

      context "when the contract is terminated before the card starts" do
        let(:terminated_at) { Time.utc(2026, 2, 15) }

        it "leaves out the card" do
          expect(described_class.starting_before_contract_end).to be_empty
        end
      end

      # A contract kept running past its planned end still stopped serving at that end.
      context "when the planned end came before the termination" do
        let(:ended_at) { Time.utc(2026, 2, 15) }
        let(:terminated_at) { Time.utc(2026, 4, 1) }

        it "leaves out the card" do
          expect(described_class.starting_before_contract_end).to be_empty
        end
      end
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:billing_anchor_date) }
    it { is_expected.to validate_presence_of(:effective_date) }

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

  describe "#inherited_billing_anchor?" do
    let(:card) { build(:contract_rate_card, effective_date: Date.new(2026, 10, 15), billing_anchor_date:) }

    context "with the contract's explicit anchor" do
      let(:billing_anchor_date) { Date.new(2026, 10, 1) }

      it { expect(card.inherited_billing_anchor?(Date.new(2026, 10, 1))).to be(true) }
    end

    context "with the card's own start day and no contract anchor" do
      let(:billing_anchor_date) { Date.new(2026, 10, 15) }

      it { expect(card.inherited_billing_anchor?(nil)).to be(true) }
    end

    context "with the card's own start day while the contract has an anchor" do
      let(:billing_anchor_date) { Date.new(2026, 10, 15) }

      it { expect(card.inherited_billing_anchor?(Date.new(2026, 10, 1))).to be(false) }
    end

    context "with any other day" do
      let(:billing_anchor_date) { Date.new(2026, 10, 5) }

      it { expect(card.inherited_billing_anchor?(nil)).to be(false) }
    end
  end

  describe "#periodic_billing_action" do
    let(:organization) { build(:organization) }
    let(:product) { build(:product, organization:) }
    let(:rate_card) do
      build(:rate_card, organization:, product:, billing_timing:, display_on_invoice:, regroup_paid_fees:)
    end
    let(:card) { build(:contract_rate_card, organization:, rate_card:) }
    let(:billing_timing) { :advance }
    let(:display_on_invoice) { false }
    let(:regroup_paid_fees) { nil }

    context "with a fixed product billed in advance" do
      let(:product) { build(:product, :fixed, organization:) }

      it { expect(card.periodic_billing_action).to eq("renew_fixed_advance") }
    end

    context "with a fixed product billed in arrears" do
      let(:product) { build(:product, :fixed, organization:) }
      let(:billing_timing) { :arrears }

      it { expect(card.periodic_billing_action).to eq("close_fixed_arrears") }
    end

    context "with recurring metered charges displayed in advance" do
      let(:display_on_invoice) { true }
      let(:product) do
        metric = build(:sum_billable_metric, organization:, recurring: true)
        build(:product, organization:, billable_metric: metric)
      end

      it { expect(card.periodic_billing_action).to eq("renew_recurring_metered_advance") }

      context "when paid fees are also regrouped" do
        let(:regroup_paid_fees) { "invoice" }

        it { expect(card.periodic_billing_action).to eq("renew_recurring_metered_advance") }
      end
    end

    context "with advance metered charges regrouped on the invoice" do
      let(:regroup_paid_fees) { "invoice" }

      it { expect(card.periodic_billing_action).to eq("regroup_paid_fees") }
    end

    context "with metered charges in arrears" do
      let(:billing_timing) { :arrears }

      it { expect(card.periodic_billing_action).to eq("close_metered_arrears") }
    end

    it "returns nil for an unsupported metered advance configuration" do
      expect(card.periodic_billing_action).to be_nil
    end
  end

  describe "#next_billing_at" do
    subject(:next_billing_at) { card.next_billing_at }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 10, 6)) }
    let(:product) { create(:product, organization:) }
    let(:rate_card) do
      create(
        :rate_card,
        organization:,
        product:,
        billing_timing:,
        display_on_invoice:,
        regroup_paid_fees:
      )
    end
    let(:billing_timing) { :advance }
    let(:display_on_invoice) { false }
    let(:regroup_paid_fees) { nil }
    let(:card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card:,
        effective_date: Date.new(2026, 10, 6),
        billing_anchor_date: Date.new(2026, 10, 6)
      )
    end

    before do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.utc(2026, 10, 6),
        billing_interval_unit: :day,
        billing_interval_count: 1
      )
      card
    end

    around do |example|
      travel_to(Time.utc(2026, 10, 7, 8, 11)) { example.run }
    end

    it "does not derive a cursor for event-only advance metered fees" do
      expect(next_billing_at).to be_nil
    end

    context "when a regular advance schedule has no operation yet" do
      let(:product) { create(:product, :fixed, organization:) }
      let(:display_on_invoice) { true }

      it "does not invent a cursor before scheduling" do
        expect(next_billing_at).to be_nil
      end
    end

    context "when cancelled operations exist" do
      let(:product) { create(:product, :fixed, organization:) }
      let(:display_on_invoice) { true }
      let(:cancelled_operation) do
        create(
          :billing_operation, organization:, customer:, contract_rate_card: card,
          billing_at: Time.utc(2026, 10, 7), target_cycle_started_at: Time.utc(2026, 10, 7),
          cancelled_at: Time.utc(2026, 10, 7),
          cancelled_causation_type: :contract_termination
        )
      end

      context "when a pending operation also exists" do
        before do
          cancelled_operation
          create(
            :billing_operation, organization:, customer:, contract_rate_card: card,
            action_type: "reconcile_advance_coverage", billing_at: Time.utc(2026, 10, 9), target_cycle_started_at: Time.utc(2026, 10, 8)
          )
          card.update!(next_billing_at: Time.utc(2026, 10, 10))
        end

        it "returns the periodic cursor independently of pending reconciliations" do
          expect(next_billing_at).to eq(Time.utc(2026, 10, 10))
        end
      end

      context "when only cancelled operations exist" do
        before { cancelled_operation }

        it "does not treat the cancelled chain as a pending due date or reseed it" do
          expect(next_billing_at).to be_nil
        end
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
