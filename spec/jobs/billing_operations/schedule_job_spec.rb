# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ScheduleJob, job: true do
  subject(:perform_job) { described_class.perform_now(customer.id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }

    before { described_class.unlock! }
    after { described_class.unlock! }
  end

  before do
    allow(BillingOperations::ScheduleService).to receive(:call!).with(customer:).and_call_original
  end

  context "when due pending operations exist" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago)
    end

    before { operation }

    it "schedules the customer and dispatches processing" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id)
      expect(BillingOperations::ScheduleService).to have_received(:call!).with(customer:)
      expect(operation.reload).to have_attributes(processed_at: nil, cancelled_at: nil)
    end
  end

  context "when scheduling creates a due periodic operation" do
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", currency: "USD", proration: true) }
    let(:billing_scope) { "segment" }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:, next_billing_at: Time.utc(2026, 11, 15),
        effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
    end

    before do
      travel_to(Time.utc(2026, 11, 15))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1), rate_properties: {"amount" => "31"})
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), rate_properties: {"amount" => "62"})
      contract_rate_card
    end

    it "persists the periodic operation and then dispatches processing" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id)

      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", reason: "periodic_continuation",
        billing_at: Time.utc(2026, 11, 15), target_cycle_started_at: Time.utc(2026, 11, 1),
        processed_at: nil
      )
    end

    context "when operation creation fails" do
      let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

      before do
        allow(BillingOperations::CreateService).to receive(:call!)
          .and_raise(BaseService::FailedResult.new(failure, "cannot schedule"))
      end

      it "does not dispatch processing without persisted scheduled work" do
        expect { perform_job }.to raise_error(BaseService::FailedResult)
        expect(BillingOperation.where(customer:)).to be_empty
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 15))
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end
    end
  end

  context "with an overdue daily backlog" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:started_at) { Time.utc(2026, 10, 31) }
    let(:contract) { create(:contract, organization:, customer:, started_at:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", currency: "USD") }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, next_billing_at: Time.utc(2026, 11, 2),
        effective_date: Date.new(2026, 10, 31), billing_anchor_date: Date.new(2026, 10, 31))
    end
    let(:completed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        billing_at: Time.utc(2026, 11, 1), target_cycle_started_at: started_at, processed_at: Time.utc(2026, 11, 1),
        coverage_ended_at: Time.utc(2026, 11, 1))
    end

    before do
      travel_to(Time.utc(2026, 11, 19))
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        billing_interval_count: 1, billing_interval_unit: "day", rate_properties: {"amount" => "31"})
      completed_operation
    end

    it "persists every due close and dispatches processing once" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id).once
      expect(contract_rate_card.billing_operations.pending.order(:billing_at).pluck(:billing_at))
        .to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(completed_operation.reload).to have_attributes(
        billing_at: Time.utc(2026, 11, 1), target_cycle_started_at: started_at, processed_at: Time.utc(2026, 11, 1)
      )
      expect(contract_rate_card.billing_operations.where(billing_at: Time.utc(2026, 11, 20)..)).to be_empty
    end
  end

  context "when a cycle-scoped rate changes within a billing cycle" do
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", currency: "USD", proration: true) }
    let(:next_billing_at) { Time.utc(2026, 11, 15) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope: "cycle",
        next_billing_at:, effective_date: Date.new(2026, 11, 1),
        billing_anchor_date: Date.new(2026, 11, 1))
    end

    before do
      travel_to(Time.utc(2026, 11, 15))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1), rate_properties: {"amount" => "31"})
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), rate_properties: {"amount" => "62"})
      contract_rate_card
    end

    it "replans at the rate change without dispatching processing" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end

    context "when the cycle closes" do
      let(:next_billing_at) { Time.utc(2026, 12, 1) }

      before { travel_to(Time.utc(2026, 12, 1)) }

      it "persists the cycle operation and dispatches processing" do
        expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id)
        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          action_type: "close_fixed_arrears", reason: "periodic_continuation",
          billing_at: Time.utc(2026, 12, 1), target_cycle_started_at: Time.utc(2026, 11, 1),
          processed_at: nil
        )
      end
    end
  end

  context "when the customer has no due pending operations" do
    let(:future_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.day.from_now)
    end
    let(:processed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago,
        processed_at: Time.current)
    end
    let(:cancelled_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago,
        cancelled_at: Time.current, cancellation_reason: :rate_change)
    end
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer) }
    let(:other_rate_card) { create(:contract_rate_card, organization:, contract: other_contract) }
    let(:other_customer_operation) do
      create(:billing_operation, organization:, customer: other_customer, contract_rate_card: other_rate_card,
        billing_at: 1.minute.ago)
    end

    before do
      future_operation
      processed_operation
      cancelled_operation
      other_customer_operation
    end

    it "does not dispatch processing for the customer" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ProcessJob)
    end
  end

  context "when scheduling fails" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago)
    end
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      operation
      allow(BillingOperations::ScheduleService).to receive(:call!).with(customer:)
        .and_raise(BaseService::FailedResult.new(failure, "cannot schedule"))
    end

    it "does not dispatch processing" do
      expect { perform_job }.to raise_error(BaseService::FailedResult)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end
end
