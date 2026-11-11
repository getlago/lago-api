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

    describe ".eligible_for_operation_scheduling" do
      let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }
      let(:organization) { create(:organization) }

      # Priced by default: an unpriced rate card is not due, which one example checks on its own.
      def card(contract: nil, priced: true, **attributes)
        contract ||= create(:contract, organization:, started_at: 1.year.ago)
        rate_card = create(:rate_card, organization:)
        create(:rate_card_rate, organization:, rate_card:) if priced

        create(:contract_rate_card, organization:, contract:, rate_card:, **attributes)
      end

      it "takes priced cards belonging to billable contracts that have started" do
        eligible = card
        card(priced: false)

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to contain_exactly(eligible)
      end

      it "includes eligible cards when product catalog is not enabled" do
        eligible = card

        expect(organization).not_to be_product_catalog_enabled
        expect(described_class.eligible_for_operation_scheduling(timestamp)).to contain_exactly(eligible)
      end

      # Bringing a termination forward can leave a card starting after the contract ends. It
      # has no window to owe anything in, so it is not due — and the calendar is never asked
      # to build a schedule that ends before it starts.
      it "leaves out a card that starts after its contract ends" do
        ending_early = create(:contract, organization:, started_at: 1.year.ago, ended_at: 1.month.ago)
        card(contract: ending_early, effective_date: 1.week.ago.to_date)

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
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
          card(contract:, effective_date: Date.new(2027, 1, 1))
        end

        # Local midnight is Dec 31 11:00 UTC, so the contract still has nine hours to run.
        it "keeps a card whose contract outlives its customer-local start" do
          still_open = card_ending_at("Pacific/Tongatapu", Time.utc(2026, 12, 31, 20))

          expect(described_class.eligible_for_operation_scheduling(timestamp)).to contain_exactly(still_open)
        end

        # Local midnight is Jan 1 12:00 UTC, after the contract ended: no window at all, and
        # letting it through makes BuildScheduleService raise on ends_at before starts_at.
        it "leaves out a card whose contract ended before its customer-local start" do
          card_ending_at("Etc/GMT+12", Time.utc(2027, 1, 1, 5))

          expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
        end
      end

      it "leaves out a card whose rate card has no price yet" do
        card(priced: false)

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
      end

      # The instant governs the whole query, not only the clock: a catch-up run for a past date
      # sees the cards that were live then, and does not lose the periods they still owe.
      it "answers for the instant it is given rather than for now" do
        past = 2.months.ago
        ended_since = card(
          contract: create(:contract, organization:, started_at: 1.year.ago, ended_at: 1.month.ago),
          effective_date: 1.year.ago.to_date
        )

        expect(described_class.eligible_for_operation_scheduling(past)).to contain_exactly(ended_since)
      end

      # Deleting a customer leaves their contracts active, so without this the card stays due
      # on every tick and the producer raises RecordNotFound loading the customer back:
      # Contract#customer is with_discarded, Customer's own default scope is not.
      it "leaves out cards of a deleted customer" do
        deleted = create(:customer, organization:)
        contract = create(:contract, organization:, customer: deleted, started_at: 1.year.ago)
        card(contract:)
        deleted.discard!

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
      end

      it "leaves out cards of contracts that are not active" do
        %w[pending terminated canceled].each do |status|
          inactive = create(:contract, organization:, status:, started_at: 1.year.ago)
          card(contract: inactive)
        end

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
      end

      it "leaves out a card whose contract has not started yet" do
        late_contract = create(:contract, organization:, started_at: timestamp + 1.day)
        card(contract: late_contract)

        expect(described_class.eligible_for_operation_scheduling(timestamp)).to be_empty
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

    it "returns the next schedule date for event-only advance metered fees" do
      expect(next_billing_at).to eq(Time.utc(2026, 10, 8))
    end

    context "when a regular advance schedule has no operation yet" do
      let(:product) { create(:product, :fixed, organization:) }
      let(:display_on_invoice) { true }

      it "keeps the billing instant of the period currently served" do
        expect(next_billing_at).to eq(Time.utc(2026, 10, 7))
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
            billing_at: Time.utc(2026, 10, 9), target_cycle_started_at: Time.utc(2026, 10, 8)
          )
        end

        it "returns the pending operation date rather than the cancelled one" do
          expect(next_billing_at).to eq(Time.utc(2026, 10, 9))
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
