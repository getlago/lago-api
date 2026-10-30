# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::DestroyService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  let(:activity_log_calls) { [] }

  before do
    allow(Utils::ActivityLog).to receive(:produce) do |*args, **kwargs, &block|
      activity_log_calls << {args:, kwargs:, block:}
    end
  end

  it "discards the card and its phases and overrides" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override)

    expect(result).to be_success
    expect(contract_rate_card.reload.discarded?).to be(true)
    expect(phase.reload.discarded?).to be(true)
    expect(override.reload.discarded?).to be(true)
  end

  it "publishes one legacy contract_rate_card.deleted pair without a snapshot" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override)

    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with(
      "contract_rate_card.deleted",
      contract_rate_card
    )
    expect(Utils::ActivityLog).to have_received(:produce).with(
      contract_rate_card,
      "contract_rate_card.deleted",
      after_commit: true
    )
    activity_call = activity_log_calls.sole
    expect(activity_call.fetch(:block)).to be_a(Proc)
    expect(activity_call.fetch(:kwargs)).to eq(after_commit: true)
    expect(phase.reload).to be_discarded
    expect(override.reload).to be_discarded
    expect(contract_rate_card.reload.rate_phases).to be_empty
    serialized_card = ::V2::ContractAppliedRateCardSerializer.new(contract_rate_card, root_name: "contract_rate_card").serialize
    expect(serialized_card).not_to have_key(:rate_phases_count)
    expect(serialized_card).not_to have_key(:rate_phases)
  end

  it "supports suppressing the card event pair for a caller-owned cascade" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override)

    expect do
      described_class.call(contract_rate_card:, emit_events: false)
    end.not_to have_enqueued_job(SendWebhookJob)
    expect(activity_log_calls.map { |call| call[:args][1] }).not_to include("contract_rate_card.deleted", "contract_rate_card.updated")
    expect(phase.reload).to be_discarded
    expect(override.reload).to be_discarded
  end

  context "when the contract is locked (active)" do
    let(:contract) { create(:contract, organization:, customer:) }

    it "fails with a contract_locked error" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      activity_call = activity_log_calls.sole
      expect(activity_call.fetch(:args).first(2)).to eq([contract_rate_card, "contract_rate_card.deleted"])
      expect(activity_call.fetch(:kwargs)).to eq(after_commit: true)
      expect(activity_call.fetch(:block).call).not_to be_success
    end
  end

  context "when the clock activated the contract since it was loaded" do
    before do
      contract_rate_card
      Contract.where(id: contract.id).update_all(status: :active) # rubocop:disable Rails/SkipsModelValidations
    end

    it "fails with a contract_locked error and keeps the card" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract_rate_card.reload).not_to be_discarded
    end
  end

  context "when the surrounding transaction rolls back", :capture_kafka_messages do
    let(:override) { create(:rate_override, organization:) }
    let(:phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override) }

    before do
      phase
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "restores the card hierarchy and suppresses both event channels", transaction: false do
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(kafka_messages).to be_empty
      expect(contract_rate_card.reload).not_to be_discarded
      expect(phase.reload).not_to be_discarded
      expect(override.reload).not_to be_discarded
    end
  end

  context "when the card is missing" do
    let(:contract_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("applied_rate_card")
    end
  end
end
