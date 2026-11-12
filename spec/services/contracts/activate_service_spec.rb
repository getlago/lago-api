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

    it "does not seed an operation for an unpriced rate card" do
      expect { result }.not_to change(BillingOperation, :count)
    end
  end

  context "with a priced rate card" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears") }
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

    it "persists the initial cursor inside activation without future operations or segments" do
      expect { result }
        .not_to change(BillingOperation, :count)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 10, 30))
      expect(LegacyBillingSegment.count).to eq(0)
    end

    it "does not reset the cursor when activation is retried" do
      result
      contract_rate_card.update!(next_billing_at: Time.utc(2026, 11, 30))

      expect(described_class.call(contract:, timestamp:)).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 30))
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
        allow(ContractRateCards::InitializeBillingClockService).to receive(:call!).and_wrap_original do |original, **attributes|
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
        expect { result }.not_to have_enqueued_job(SendWebhookJob)
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
        expect(result).not_to be_success
        expect(contract.reload).to be_pending
        expect(contract_rate_card.reload.next_billing_at).to be_nil
        expect(failure_card.reload.next_billing_at).to be_nil
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
