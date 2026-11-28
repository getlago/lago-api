# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::PublishService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:started_at) { 1.month.from_now.beginning_of_day }
  let(:contract) { create(:contract, :draft, organization:, customer:, started_at:) }

  before do
    allow(Utils::ActivityLog).to receive(:produce)
    allow(Utils::ActivityLog).to receive(:produce_after_commit)
  end

  it "makes a draft whose start is ahead pending, which the clock then starts" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.published", contract)

    expect(result).to be_success
    expect(contract.reload).to be_pending
    expect(SendWebhookJob).not_to have_been_enqueued.with("contract.started", anything)
    expect(Contracts::ReplayDraftUsageJob).not_to have_been_enqueued
    expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.published")

    travel_to(started_at) { Contracts::ActivateAllPendingService.call }
    expect(Contracts::ActivateJob).to have_been_enqueued.with(contract)
  end

  context "with activity logs", :capture_kafka_messages, transaction: false do
    before do
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      allow(Utils::ActivityLog).to receive(:produce_after_commit).and_call_original
    end

    it "records the publication" do
      expect(result).to be_success

      payload = JSON.parse(kafka_messages.sole.fetch(:payload))
      expect(payload).to include("activity_type" => "contract.published", "resource_id" => contract.id)
      expect(payload.dig("activity_object", "status")).to eq("pending")
    end

    context "when the start has passed" do
      let(:started_at) { 1.month.ago }

      it "records the publication, then the start" do
        expect(result).to be_success

        payloads = kafka_messages.map { JSON.parse(it.fetch(:payload)) }
        expect(payloads.map { it.fetch("activity_type") }).to eq(%w[contract.published contract.started])
        expect(payloads.map { it.dig("activity_object", "status") }).to eq(%w[active active])
      end
    end
  end

  context "when the start has passed" do
    let(:started_at) { Time.zone.parse("2026-09-30T00:00:00Z") }
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

    it "activates it and schedules billing from its start, catching up the elapsed periods" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).exactly(2).times

      expect(SendWebhookJob).to have_been_enqueued.with("contract.published", contract)
      expect(SendWebhookJob).to have_been_enqueued.with("contract.started", contract)
      expect(contract.reload).to be_active
      expect(contract_rate_card.billing_operations.sole).to have_attributes(
        action_type: "renew_fixed_advance", reason: "contract_activation",
        billing_at: started_at, target_cycle_started_at: started_at
      )
    end

    it "replays the usage received in advance while it was a draft, up to the publication" do
      freeze_time do
        expect { result }.to have_enqueued_job_after_commit(Contracts::ReplayDraftUsageJob).with(contract, Time.current)
      end
    end

    it "activates it once when the publication is retried" do
      described_class.call(contract:)

      expect { described_class.call(contract: Contract.find(contract.id)) }.not_to have_enqueued_job
      expect(contract.reload).to be_active
      expect(BillingOperation.count).to eq(1)
      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.published").once
    end

    context "when the activation fails" do
      before do
        failure = Contracts::ActivateService::Result.new
          .single_validation_failure!(field: :external_id, error_code: "active_contract_exists")
        allow(Contracts::ActivateService).to receive(:call!).and_raise(failure.error)
      end

      it "keeps the draft, without notifying the move to pending" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result.error.messages).to eq(external_id: ["active_contract_exists"])
        expect(contract.reload).to be_draft
      end
    end
  end

  %i[pending active].each do |status|
    context "when the contract is already #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, started_at:) }

      it "returns it unchanged without notifying" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).to be_success
        expect(result.contract).to eq(contract)
        expect(contract.reload.status).to eq(status.to_s)
        expect(Utils::ActivityLog).not_to have_received(:produce_after_commit)
      end
    end
  end

  context "when a pending contract's start has passed since it was published" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: 1.day.ago) }

    it "activates it, as the first publication would have, without publishing it again" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.started", contract)

      expect(contract.reload).to be_active
      expect(SendWebhookJob).not_to have_been_enqueued.with("contract.published", anything)
    end
  end

  %i[terminated canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, started_at:) }

      it "refuses to publish it" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result.error.messages).to eq(contract: ["cannot_publish"])
        expect(contract.reload.status).to eq(status.to_s)
      end
    end
  end

  context "when the contract was canceled since it was loaded" do
    before { Contract.where(id: contract.id).update_all(status: :canceled) } # rubocop:disable Rails/SkipsModelValidations

    it "leaves it canceled" do
      expect(result.error.messages).to eq(contract: ["cannot_publish"])
      expect(contract.reload).to be_canceled
    end
  end

  context "when the contract has no start date" do
    before { contract.update!(started_at: nil) }

    it "refuses to publish it, as the clock would never start it" do
      expect(result.error.messages).to eq(started_at: ["value_is_mandatory"])
      expect(contract.reload).to be_draft
    end
  end

  context "when the contract already ended" do
    let(:started_at) { 2.months.ago }

    before { contract.update!(ended_at: 1.day.ago) }

    it "refuses to publish it" do
      expect(result.error.messages).to eq(ended_at: ["already_ended"])
      expect(contract.reload).to be_draft
    end
  end

  context "when the contract ends now" do
    let(:started_at) { 2.months.ago }

    before do
      freeze_time
      contract.update!(ended_at: Time.current)
    end

    it "refuses to publish it" do
      expect(result.error.messages).to eq(ended_at: ["already_ended"])
      expect(contract.reload).to be_draft
    end
  end

  context "when the contract ends in the future" do
    let(:started_at) { 1.month.ago }

    before { contract.update!(ended_at: 1.day.from_now) }

    it "activates it" do
      expect(result).to be_success
      expect(contract.reload).to be_active
    end
  end

  context "when the contract starts now" do
    let(:started_at) { Time.current }

    before { freeze_time }

    it "activates it" do
      expect(result).to be_success
      expect(contract.reload).to be_active
    end
  end

  context "when the customer was deleted" do
    before { customer.discard! }

    it "refuses to publish a contract that could never start" do
      expect(result.error.messages).to eq(customer: ["customer_deleted"])
      expect(contract.reload).to be_draft
    end
  end

  context "when an active contract shares its external id" do
    before { create(:contract, organization:, customer:, external_id: contract.external_id) }

    it "keeps the draft" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result.error.messages).to eq(external_id: ["active_contract_exists"])
      expect(contract.reload).to be_draft
    end
  end

  context "when a pending contract shares its external id" do
    before { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

    it "keeps the draft" do
      expect(result.error.messages).to eq(external_id: ["value_already_exists"])
      expect(contract.reload).to be_draft
    end
  end

  context "when a pending contract commits after the sibling check" do
    before do
      # Inserted right before the move to pending, so only the unique index catches it.
      allow(contract).to receive(:update!).and_wrap_original do |original, *args, **kwargs|
        create(:contract, :pending, organization:, customer:, external_id: contract.external_id)
        original.call(*args, **kwargs)
      end
    end

    it "returns the same validation error instead of raising" do
      expect(result.error.messages).to eq(external_id: ["value_already_exists"])
      expect(contract.reload).to be_draft
    end
  end

  context "when the billing schedule is locked" do
    before { allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

    it "returns a concurrency failure and keeps the draft" do
      expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
      expect(contract.reload).to be_draft
    end
  end

  context "without a contract" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
