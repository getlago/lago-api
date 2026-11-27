# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ScheduleService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:contract) { create(:contract, organization:, customer:, started_at:) }
  let(:started_at) { Time.utc(2026, 1, 1) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", currency: "USD", proration: true) }
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from, rate_properties: {"amount" => "31"})
  end
  let(:rate_effective_from) { started_at }
  let(:effective_date) { started_at.to_date }
  let(:cursor) { Time.utc(2026, 2, 1) }
  let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:cycle) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:, next_billing_at: cursor,
      effective_date:, billing_anchor_date: effective_date)
  end
  let(:timestamp) { cursor }

  before do
    rate
    contract_rate_card
  end

  it "persists one periodic operation and returns it without advancing the cursor" do
    expect(result).to be_success
    expect(result.billing_operations.sole).to have_attributes(
      organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
      reason: "periodic_continuation", billing_at: cursor,
      target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: nil, cancelled_at: nil
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(cursor)

    expect(described_class.call!(customer:, timestamp:).billing_operations).to be_empty
    expect(contract_rate_card.billing_operations.count).to eq(1)
  end

  context "when a due card has no periodic action" do
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
    end
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: false, currency: "USD")
    end

    it "clears the clock without persisting an operation" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(ContractRateCard.due_for_billing(timestamp)).not_to include(contract_rate_card)
    end
  end

  context "with fixed advance billing" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }
    let(:cursor) { started_at }

    it "persists the opening obligation at the start of coverage" do
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "renew_fixed_advance", billing_at: started_at, target_cycle_started_at: started_at
      )
    end
  end

  context "with a completed operation in the current cycle" do
    let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:segment) }
    let(:completed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "contract_activation", billing_at: Time.utc(2026, 1, 15),
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 15))
    end

    before do
      completed_operation
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15), rate_properties: {"amount" => "62"})
    end

    it "continues the same cycle at the next due date" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1),
        coverage_started_at: Time.utc(2026, 1, 15), coverage_ended_at: Time.utc(2026, 2, 1)
      )
      expect(result.billing_operations.sole.reload.segments.sole).to have_attributes(
        started_at: Time.utc(2026, 1, 15), ended_at: Time.utc(2026, 2, 1)
      )
      expect(completed_operation.reload.processed_at).to eq(Time.utc(2026, 1, 15))
    end
  end

  context "with a completed operation from the prior cycle" do
    let(:cursor) { Time.utc(2026, 3, 1) }
    let(:completed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: Time.utc(2026, 2, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 2, 1))
    end

    before { completed_operation }

    it "starts the next planned cycle after the latest completion" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 2, 1)
      )
    end
  end

  context "when an advance card was terminated after its last renewal" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at:, terminated_at: Time.utc(2026, 1, 20))
    end
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }
    let(:cursor) { Time.utc(2026, 2, 1) }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
        reason: "contract_activation", billing_at: started_at,
        target_cycle_started_at: started_at, processed_at: started_at)
    end

    it "clears the clock, as no coverage is left to bill" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(ContractRateCard.due_for_billing(timestamp)).not_to include(contract_rate_card)
    end
  end

  context "when the schedule has no obligation at all" do
    let(:contract) { create(:contract, organization:, customer:, started_at:, ended_at: Time.utc(2026, 1, 20)) }
    let(:rate_effective_from) { Time.utc(2026, 1, 25) }
    let(:cursor) { started_at }

    it "clears the clock without persisting an operation" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "when the schedule cannot be built" do
    before do
      allow(Billing::RateCards::BuildScheduleService).to receive(:call!)
        .and_return(Billing::RateCards::BuildScheduleService::Result.new)
    end

    it "keeps the existing cursor without creating operations" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "with a future activation and a new rate in the current cycle" do
    let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:segment) }
    let(:started_at) { Time.utc(2026, 11, 1) }
    let(:effective_date) { Date.new(2026, 11, 1) }
    let(:cursor) { Time.utc(2026, 11, 15) }
    let(:pending_activation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "contract_activation", billing_at: Time.utc(2026, 12, 1),
        target_cycle_started_at: Time.utc(2026, 11, 1))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), rate_properties: {"amount" => "62"})
      pending_activation
    end

    it "schedules the new due obligation without retiming the activation" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: Time.utc(2026, 11, 1),
        reason: "periodic_continuation"
      )
      expect(pending_activation.reload).to have_attributes(
        billing_at: Time.utc(2026, 12, 1), processed_at: nil, reason: "contract_activation"
      )
    end

    context "when the future activation falls before the next natural close" do
      let(:pending_activation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
          reason: "contract_activation", billing_at: Time.utc(2026, 11, 20),
          target_cycle_started_at: Time.utc(2026, 11, 1))
      end

      it "does not use the future pending operation as the anchor" do
        expect(result.billing_operations.sole.billing_at).to eq(Time.utc(2026, 11, 15))
        expect(pending_activation.reload.processed_at).to be_nil
      end
    end

    context "when the scope covers the cycle" do
      let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:cycle) }

      it "keeps the activation and does not schedule an intermediate close" do
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          id: pending_activation.id, billing_at: Time.utc(2026, 12, 1),
          processed_at: nil, reason: "contract_activation"
        )
      end
    end
  end

  context "with overdue daily obligations" do
    let(:started_at) { Time.utc(2026, 10, 31) }
    let(:cursor) { Time.utc(2026, 11, 2) }
    let(:timestamp) { Time.utc(2026, 11, 19) }
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        billing_interval_count: 1, billing_interval_unit: "day", rate_properties: {"amount" => "31"})
    end
    let(:anchor_at) { Time.utc(2026, 11, 1) }
    let(:anchor_cycle) { started_at }
    let(:anchor_action) { "close_fixed_arrears" }
    let(:anchor_processed_at) { anchor_at }
    let(:anchor) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: anchor_action,
        billing_at: anchor_at, target_cycle_started_at: anchor_cycle, processed_at: anchor_processed_at)
    end

    before { anchor }

    it "creates every missing due operation without advancing the processing cursor" do
      expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations.where(billing_at: Time.utc(2026, 11, 20)..)).to be_empty
      expect(described_class.call!(customer:, timestamp:).billing_operations).to be_empty
    end

    context "when the anchor is pending" do
      let(:anchor_processed_at) { nil }

      it "preserves the pending operation and fills the following days" do
        expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
        expect(anchor.reload.processed_at).to be_nil
      end
    end

    context "with advance billing" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }
      let(:anchor_action) { "renew_fixed_advance" }
      let(:anchor_cycle) { anchor_at }

      it "persists all missing renewals through the cutoff" do
        expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
        expect(result.billing_operations.map(&:action_type).uniq).to eq(["renew_fixed_advance"])
      end
    end

    context "with a Los Angeles customer" do
      let(:timezone) { "America/Los_Angeles" }
      let(:started_at) { Time.utc(2026, 10, 31, 7) }
      let(:effective_date) { Date.new(2026, 10, 31) }
      let(:anchor_at) { Time.utc(2026, 11, 1, 7) }
      let(:cursor) { Time.utc(2026, 11, 2, 8) }
      let(:timestamp) { Time.utc(2026, 11, 19, 8) }

      it "uses local billing boundaries across daylight saving" do
        expect(result.billing_operations.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it, 8) })
      end
    end

    context "when a later operation creation fails" do
      let(:calls) { [] }
      let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

      before do
        allow(BillingOperations::CreateService).to receive(:call!).and_wrap_original do |original, **attributes|
          calls << attributes
          raise BaseService::FailedResult.new(failure, "cannot schedule") if calls.size == 2

          original.call(**attributes)
        end
      end

      it "rolls back the partial batch and reset cursor" do
        expect(result).to be_failure
        expect(result.billing_operations).to be_empty
        expect(contract_rate_card.billing_operations.reload).to eq([anchor])
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      end
    end
  end

  context "with a finite terminated schedule" do
    let(:started_at) { Time.utc(2026, 11, 1) }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at:,
        ended_at: Time.utc(2026, 11, 4), terminated_at: Time.utc(2026, 11, 5))
    end
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        billing_interval_count: 1, billing_interval_unit: "day", rate_properties: {"amount" => "31"})
    end
    let(:cursor) { Time.utc(2026, 11, 2) }
    let(:timestamp) { Time.utc(2026, 11, 6) }

    it "fills all remaining due closes even without a future obligation" do
      expect(result.billing_operations.map(&:billing_at)).to eq(
        [Time.utc(2026, 11, 2), Time.utc(2026, 11, 3), Time.utc(2026, 11, 5)]
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(described_class.call!(customer:, timestamp:).billing_operations).to be_empty
    end
  end

  context "with an activation already matching the planned operation" do
    let(:pending_activation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "contract_activation", billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { pending_activation }

    it "does not create a duplicate operation" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations).to eq([pending_activation])
    end
  end

  context "with other customers' due cards" do
    let(:other_customer) { create(:customer, organization:, timezone: "UTC") }
    let(:other_contract) { create(:contract, organization:, customer: other_customer, started_at:) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:, next_billing_at: cursor,
        effective_date:, billing_anchor_date: effective_date)
    end

    before { other_card }

    it "only schedules operations for the requested customer" do
      expect(result.billing_operations.sole.customer_id).to eq(customer.id)
      expect(other_card.billing_operations).to be_empty
    end
  end

  context "with a due card from another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization, timezone: "UTC") }
    let(:other_contract) { create(:contract, organization: other_organization, customer: other_customer, started_at:) }
    let(:other_product) { create(:product, :fixed, organization: other_organization) }
    let(:other_rate_card) do
      create(:rate_card, organization: other_organization, product: other_product, billing_timing: "arrears", currency: "USD")
    end
    let(:other_rate) do
      create(:rate_card_rate, organization: other_organization, rate_card: other_rate_card, effective_from: started_at,
        rate_properties: {"amount" => "31"})
    end
    let(:other_card) do
      create(:contract_rate_card, organization: other_organization, contract: other_contract, rate_card: other_rate_card,
        next_billing_at: cursor, effective_date:, billing_anchor_date: effective_date)
    end

    before do
      other_rate
      other_card
    end

    it "does not schedule the foreign tenant's operation" do
      expect(result.billing_operations.sole.customer_id).to eq(customer.id)
      expect(other_card.billing_operations).to be_empty
    end
  end

  context "with a future billing cursor" do
    let(:cursor) { Time.utc(2026, 3, 1) }
    let(:timestamp) { cursor - 1.day }

    it "does not create an operation before the card is due" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "when the next planned operation is after the timestamp" do
    let(:rate_effective_from) { Time.utc(2026, 2, 15) }

    it "does not persist a future plan, and moves the cursor to it" do
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with metered advance billing that has no periodic action" do
    let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg, recurring: false) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }

    it "does not create periodic operations" do
      expect(contract_rate_card.periodic_billing_action).to be_nil
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
    end
  end

  context "with a Los Angeles customer timezone" do
    let(:timezone) { "America/Los_Angeles" }
    let(:cursor) { Time.utc(2026, 2, 1, 8) }

    it "uses local midnight for the initial cycle start" do
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1, 8)
      )
    end
  end

  context "when a later card creation fails" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at:) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:, next_billing_at: cursor,
        effective_date:, billing_anchor_date: effective_date)
    end
    let(:calls) { [] }
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      other_card
      allow(BillingOperations::CreateService).to receive(:call!).and_wrap_original do |original, **attributes|
        calls << attributes.fetch(:contract_rate_card).id
        if calls.one?
          original.call(**attributes)
        else
          raise BaseService::FailedResult.new(failure, "cannot schedule")
        end
      end
    end

    it "rolls back all inserted operations and returns no partial records" do
      expect(result).to be_failure
      expect(result.billing_operations).to be_empty
      expect(BillingOperation.where(customer:)).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(other_card.reload.next_billing_at).to eq(cursor)
    end
  end

  it "returns not found when the customer is missing" do
    expect(described_class.call(customer: nil, timestamp:)).to be_failure
  end
end
