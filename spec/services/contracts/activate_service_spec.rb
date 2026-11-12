# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ActivateService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:started_at) { Time.zone.parse("2026-09-30T00:00:00Z") }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at:) }
  let(:timestamp) { started_at }

  before do
    allow(Utils::ActivityLog).to receive(:produce)
    allow(Utils::ActivityLog).to receive(:produce_after_commit)
  end

  it "activates a pending contract whose start has arrived" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.started", contract)
    expect(result).to be_success
    expect(contract.reload).to be_active
    expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.started")
  end

  it "publishes started only once across repeated activation attempts" do
    expect { described_class.call(contract:, timestamp:) }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.started", contract)

    expect { described_class.call(contract:, timestamp:) }.not_to have_enqueued_job(SendWebhookJob)
    expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.started").once
  end

  it "enqueues the customer's billing directly after activation commits" do
    expect { result }.to have_enqueued_job_after_commit(BillingOperations::ProcessJob).with(customer.id)
  end

  context "with rate cards" do
    let(:queries) { [] }

    before { create(:contract_rate_card, organization:, contract:) }

    # Card and phase edits take the card lock, so holding it serializes them with activation.
    it "locks the cards while activating" do
      ActiveSupport::Notifications.subscribed(->(*, payload) { queries << payload[:sql] }, "sql.active_record") { result }

      expect(queries).to include(a_string_matching(/FROM "contract_rate_cards".*FOR UPDATE/m))
    end

    it "does not create an operation for an unpriced rate card" do
      expect { result }.not_to change(BillingOperation, :count)
    end
  end

  context "when the product catalog is disabled" do
    let(:organization) { create(:organization) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }
    let(:contract_rate_card) do
      create(
        :contract_rate_card, organization:, contract:, rate_card:,
        effective_date: started_at.to_date, billing_anchor_date: started_at.to_date
      )
    end

    before do
      contract_rate_card
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at, billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "resets the clock and creates the initial operation" do
      expect { result }.to change(BillingOperation, :count).by(1)
      expect(contract_rate_card.reload.next_billing_at).to eq(started_at)
      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "renew_fixed_advance", causation_type: "contract_activation",
        billing_at: started_at, target_cycle_started_at: started_at
      )
    end
  end

  context "with event-only usage" do
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
    end
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }
    let(:contract_rate_card) do
      create(
        :contract_rate_card, organization:, contract:, rate_card:,
        effective_date: started_at.to_date, billing_anchor_date: started_at.to_date
      )
    end

    before do
      contract_rate_card
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at, billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "does not create a periodic operation" do
      expect(contract_rate_card.periodic_billing_action).to be_nil
      expect { result }.not_to change(BillingOperation, :count)
    end
  end

  context "with a priced rate card" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears") }
    let(:rate_effective_from) { started_at }
    let(:contract_rate_card) do
      create(
        :contract_rate_card, organization:, contract:, rate_card:,
        effective_date: started_at.to_date, billing_anchor_date: started_at.to_date
      )
    end

    before do
      contract_rate_card
      create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from, billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "persists the initial operation and cursor without predicted segments" do
      expect { result }.to change(BillingOperation, :count).by(1)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 30))
      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_activation",
        billing_at: Time.utc(2026, 10, 30), target_cycle_started_at: started_at
      )
      expect(LegacyBillingSegment.count).to eq(0)
    end

    it "builds one schedule for resetting the cursor and planning the operation" do
      allow(Billing::RateCards::BuildScheduleService).to receive(:call).and_call_original

      result

      expect(Billing::RateCards::BuildScheduleService).to have_received(:call).once
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 30))
      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 10, 30), target_cycle_started_at: started_at
      )
    end

    context "when a rate card schedule cannot be built" do
      let(:failed_product) { create(:product, :fixed, organization:) }
      let(:failed_rate_card) { create(:rate_card, organization:, product: failed_product, billing_timing: "advance") }
      let(:failed_card) do
        create(
          :contract_rate_card, organization:, contract:, rate_card: failed_rate_card,
          effective_date: started_at.to_date, billing_anchor_date: started_at.to_date,
          next_billing_at: Time.utc(2026, 11, 30)
        )
      end
      let(:schedule_failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

      before do
        failed_card
        create(:rate_card_rate, organization:, rate_card: failed_rate_card, effective_from: started_at, billing_interval_count: 1, billing_interval_unit: "month")
        allow(Billing::RateCards::BuildScheduleService).to receive(:call).and_wrap_original do |original, **attributes|
          if attributes.fetch(:contract_rate_card).id == failed_card.id
            schedule_failure
          else
            original.call(**attributes)
          end
        end
      end

      it "skips the card while activating and scheduling other cards" do
        expect(result).to be_success
        expect(contract.reload).to be_active
        expect(failed_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 30))
        expect(failed_card.billing_operations).to be_empty
        expect(contract_rate_card.billing_operations.sole).to have_attributes(causation_type: "contract_activation")
      end
    end

    context "when the contract starts at midday" do
      let(:started_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

      it "plans from the start of the effective day" do
        result

        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          billing_at: Time.utc(2026, 10, 30), target_cycle_started_at: Time.utc(2026, 9, 30)
        )
      end
    end

    context "when the first rate starts after the contract" do
      let(:rate_effective_from) { started_at + 15.days }

      it "targets the first priced cycle and its billing date" do
        result

        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          causation_type: "contract_activation", billing_at: Time.utc(2026, 10, 30),
          target_cycle_started_at: started_at
        )
      end
    end

    it "does not reset the cursor when activation is retried" do
      result
      contract_rate_card.update!(next_billing_at: Time.utc(2026, 11, 30))

      expect(described_class.call(contract:, timestamp:)).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 30))
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end

    context "when the card bills in advance" do
      let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance") }

      it "persists an operation for the current cycle at activation" do
        expect { result }.to change(BillingOperation, :count).by(1)

        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          action_type: "renew_fixed_advance", causation_type: "contract_activation",
          billing_at: started_at, target_cycle_started_at: started_at
        )
      end
    end

    context "when paid fees are regrouped after their service" do
      let(:billable_metric) do
        create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
      end
      let(:product) { create(:product, organization:, billable_metric:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing: "advance", regroup_paid_fees: "invoice", display_on_invoice: false)
      end

      it "aligns the initial operation and cursor with the end of the first service segment" do
        result

        expect(contract_rate_card.billing_operations.sole).to have_attributes(
          action_type: "regroup_paid_fees", billing_at: Time.utc(2026, 10, 30), target_cycle_started_at: started_at
        )
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 30))
      end
    end

    context "when operation persistence fails" do
      before do
        contract_rate_card
        allow(BillingOperation).to receive(:new).and_wrap_original do |original, *args, **kwargs, &block|
          operation = original.call(*args, **kwargs, &block)
          if operation.contract_rate_card_id == contract_rate_card.id
            operation.errors.add(:billing_at, :invalid)
            allow(operation).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(operation))
          end
          operation
        end
      end

      it "rolls back the activation, cursor and notifications" do
        previous_cursor = contract_rate_card.reload.next_billing_at
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).not_to be_success
        expect(contract.reload).to be_pending
        expect(contract_rate_card.reload.next_billing_at).to eq(previous_cursor)
        expect(contract_rate_card.billing_operations).to be_empty
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end
    end

    context "when cursor persistence fails after an earlier card was seeded" do
      let(:failure_product) { create(:product, :fixed, organization:) }
      let(:failure_rate_card) { create(:rate_card, organization:, product: failure_product, billing_timing: "advance") }
      let(:failure_card) do
        create(
          :contract_rate_card, organization:, contract:, rate_card: failure_rate_card,
          effective_date: started_at.to_date, billing_anchor_date: started_at.to_date
        )
      end
      let(:operation_writes) { [] }

      before do
        failure_card
        create(:rate_card_rate, organization:, rate_card: failure_rate_card, effective_from: started_at, billing_interval_count: 1, billing_interval_unit: "month")
        allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_wrap_original do |original, **attributes|
          operation_writes << attributes
          if operation_writes.size == 2
            failure_card.errors.add(:next_billing_at, :invalid)
            failure = BaseService::Result.new.record_validation_failure!(record: failure_card)
            raise BaseService::FailedResult.new(failure, "cursor failed")
          end

          original.call(**attributes)
        end
      end

      it "rolls back activation, cursors and started notifications" do
        expect { result }
          .to not_have_enqueued_job(SendWebhookJob)
          .and not_change { [contract_rate_card.reload.next_billing_at, failure_card.reload.next_billing_at] }
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
        expect(result).not_to be_success
        expect(contract.reload).to be_pending
        expect(BillingOperation.where(contract_rate_card_id: [contract_rate_card.id, failure_card.id])).to be_empty
        expect(LegacyBillingSegment.where(contract_rate_card_id: [contract_rate_card.id, failure_card.id])).to be_empty
      end
    end
  end

  context "with cards still starting on a previous start date" do
    let(:inherited_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: Date.new(2026, 10, 15),
        billing_anchor_date: Date.new(2026, 10, 15)
      )
    end
    let(:anchored_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: Date.new(2026, 10, 15),
        billing_anchor_date: Date.new(2026, 10, 1)
      )
    end
    let(:current_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: Date.new(2026, 9, 30),
        billing_anchor_date: Date.new(2026, 9, 20)
      )
    end

    before do
      inherited_card
      anchored_card
      current_card
    end

    it "starts them with the contract, keeping an anchor set on a card" do
      result

      expect(inherited_card.reload).to have_attributes(effective_date: Date.new(2026, 9, 30), billing_anchor_date: Date.new(2026, 9, 30))
      expect(anchored_card.reload).to have_attributes(effective_date: Date.new(2026, 9, 30), billing_anchor_date: Date.new(2026, 10, 1))
    end

    it "leaves a card already starting with the contract as it is" do
      result

      expect(current_card.reload).to have_attributes(effective_date: Date.new(2026, 9, 30), billing_anchor_date: Date.new(2026, 9, 20))
    end
  end

  context "with a card whose cadence changed while the contract was pending" do
    let(:rate_card) { create(:rate_card, organization:) }
    # The target cycle is resolved again from the current cadence at activation.
    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card:,
        effective_date: Date.new(2026, 9, 30),
        billing_anchor_date: Date.new(2026, 9, 30)
      )
    end

    around { |example| travel_to(Time.zone.parse("2026-10-20T10:00:00Z")) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-09-01"), billing_interval_unit: "week")
      create(:rate_phase, :contract_level, organization:, contract_rate_card:)
    end

    # The first weekly period remains anchored to the card's original effective date.
    it "resolves the original target cycle from the current cadence" do
      result

      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-07"))
      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "close_metered_arrears", causation_type: "contract_activation",
        billing_at: Time.zone.parse("2026-10-07"), target_cycle_started_at: Time.zone.parse("2026-09-30")
      )
    end
  end

  context "when the start has not arrived yet" do
    let(:timestamp) { started_at - 1.second }

    it "keeps the contract pending" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).to be_success
      expect(contract.reload).to be_pending
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.started", any_args)
    end
  end

  context "when the customer was deleted since the activation was enqueued" do
    before { customer.discard! }

    it "keeps the contract pending without scheduling billing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).to be_success
      expect(contract.reload).to be_pending
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.started", any_args)
    end
  end

  context "when the contract was canceled since it was loaded" do
    before { Contract.where(id: contract.id).update_all(status: :canceled) } # rubocop:disable Rails/SkipsModelValidations

    it "leaves it canceled" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).to be_success
      expect(contract.reload).to be_canceled
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.started", any_args)
    end
  end

  context "when an active contract shares its external id" do
    before { create(:contract, organization:, customer:, external_id: contract.external_id) }

    it "fails instead of leaving the replacement waiting unnoticed" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:external_id]).to eq(["active_contract_exists"])
      expect(contract.reload).to be_pending
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.started", any_args)
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
