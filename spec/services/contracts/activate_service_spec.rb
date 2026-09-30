# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ActivateService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:started_at) { Time.zone.parse("2026-09-30T00:00:00Z") }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at:) }
  let(:timestamp) { started_at }

  it "activates a pending contract whose start has arrived" do
    expect(result).to be_success
    expect(contract.reload).to be_active
  end

  it "schedules the customer's billing" do
    result

    expect(BillingSegments::ScheduleJob).to have_been_enqueued.with(customer.id)
  end

  context "with rate cards" do
    let(:queries) { [] }

    before { create(:contract_rate_card, organization:, contract:) }

    # Card and phase edits take the card lock, so holding it serializes them with activation.
    it "locks the cards while activating" do
      ActiveSupport::Notifications.subscribed(->(*, payload) { queries << payload[:sql] }, "sql.active_record") { result }

      expect(queries).to include(a_string_matching(/FROM "contract_rate_cards".*FOR UPDATE/m))
    end
  end

  context "when the start has not arrived yet" do
    let(:timestamp) { started_at - 1.second }

    it "keeps the contract pending" do
      expect(result).to be_success
      expect(contract.reload).to be_pending
      expect(BillingSegments::ScheduleJob).not_to have_been_enqueued
    end
  end

  context "when the customer was deleted since the activation was enqueued" do
    before { customer.discard! }

    it "keeps the contract pending without scheduling billing" do
      expect(result).to be_success
      expect(contract.reload).to be_pending
      expect(BillingSegments::ScheduleJob).not_to have_been_enqueued
    end
  end

  context "when the contract was canceled since it was loaded" do
    before { Contract.where(id: contract.id).update_all(status: :canceled) } # rubocop:disable Rails/SkipsModelValidations

    it "leaves it canceled" do
      expect(result).to be_success
      expect(contract.reload).to be_canceled
      expect(BillingSegments::ScheduleJob).not_to have_been_enqueued
    end
  end

  context "when an active contract shares its external id" do
    before { create(:contract, organization:, customer:, external_id: contract.external_id) }

    it "fails instead of leaving the replacement waiting unnoticed" do
      expect(result).not_to be_success
      expect(result.error.messages[:external_id]).to eq(["active_contract_exists"])
      expect(contract.reload).to be_pending
      expect(BillingSegments::ScheduleJob).not_to have_been_enqueued
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
