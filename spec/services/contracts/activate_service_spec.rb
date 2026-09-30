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

  context "when the start has not arrived yet" do
    let(:timestamp) { started_at - 1.second }

    it "keeps the contract pending" do
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

    it "keeps the replacement pending" do
      expect(result).to be_success
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
