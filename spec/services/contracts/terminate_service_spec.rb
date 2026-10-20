# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  it "terminates an active contract" do
    freeze_time do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
      expect(contract.canceled_at).to be_nil
    end
  end

  # Started Aug 1 and terminated Aug 21 at 14:00, both in the customer's time: the termination
  # day is served, so it is paid, which makes 21 of August's 31 days.
  context "when the contract has rate cards" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:started_at) { Time.find_zone("America/New_York").parse("2026-08-01 00:00:00") }
    let(:terminated_at) { Time.find_zone("America/New_York").parse("2026-08-21 14:00:00") }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
    let(:arrears_card) { card(billing_timing: "arrears") }
    let(:advance_card) { card(billing_timing: "advance") }

    def card(billing_timing:, priced: true)
      rate_card = create(:rate_card, organization:, billing_timing:, proration: false, product: create(:product, :fixed, organization:))
      if priced
        create(:rate_card_rate, organization:, rate_card:, effective_from: started_at - 1.month, billing_interval_count: 1, billing_interval_unit: "month")
      end

      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 8, 1),
        billing_anchor_date: Date.new(2026, 8, 1),
        next_billing_at: started_at
      )
    end

    def segments_of(card) = BillingSegment.where(contract_rate_card: card)

    before do
      arrears_card
      advance_card
      BillingSegments::ScheduleService.call!(customer:, timestamp: started_at)
    end

    it "bills the arrears card for the days served, the termination day included, even without proration" do
      travel_to(terminated_at) { result }

      expect(segments_of(arrears_card).sole).to have_attributes(
        started_at:,
        ended_at: BillingSegment.inclusive_end(terminated_at),
        billing_at: terminated_at,
        proration_ratio: (BigDecimal(21) / 31).round(10),
        status: "pending"
      )
    end

    it "bills nothing more for the advance card, paid for the month already" do
      expect { travel_to(terminated_at) { result } }.not_to change { segments_of(advance_card).pluck(:id) }
    end

    it "stops every card's clock" do
      travel_to(terminated_at) { result }

      expect([arrears_card.reload.next_billing_at, advance_card.reload.next_billing_at]).to eq([nil, nil])
    end

    it "invoices the closed period once the termination commits" do
      expect { travel_to(terminated_at) { result } }
        .to have_enqueued_job_after_commit(BillingSegments::ProcessJob).with(customer.id)
    end

    # Time is not frozen here: a real clock carries nanoseconds the database drops, and the
    # final slice must still fall due at the instant stored.
    it "closes the period at whatever instant it terminates" do
      result

      expect(segments_of(arrears_card).order(:started_at).last.ended_at)
        .to eq(BillingSegment.inclusive_end(contract.reload.terminated_at))
    end

    context "when a card has no price yet" do
      let(:unpriced_card) { card(billing_timing: "arrears", priced: false) }

      before { unpriced_card }

      it "terminates without billing it" do
        travel_to(terminated_at) { result }

        expect(result).to be_success
        expect(segments_of(unpriced_card)).to be_empty
      end
    end

    context "when closing the billing fails" do
      before do
        allow(BillingSegments::ScheduleFinalSegmentsService).to receive(:call!)
          .and_raise(BaseService::ValidationFailure.new(BaseResult.new, messages: {billing_segment: ["overlapping_periods"]}))
      end

      it "leaves the contract active" do
        expect(result.error.messages).to eq({billing_segment: ["overlapping_periods"]})
        expect(contract.reload.status).to eq("active")
      end
    end

    context "when the clock holds the customer's billing lock" do
      before do
        allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "reports the conflict and leaves the contract active" do
        expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
        expect(contract.reload.status).to eq("active")
      end
    end
  end

  context "when given the instant it ends at" do
    subject(:result) { described_class.call(contract:, timestamp:) }

    let(:timestamp) { 1.hour.ago.change(usec: 0) }

    it "terminates it at that instant" do
      expect(result).to be_success
      expect(contract.reload.terminated_at).to eq(timestamp)
    end
  end

  context "when the clock activated the contract since it was loaded" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    before { Contract.where(id: contract.id).update_all(status: :active) } # rubocop:disable Rails/SkipsModelValidations

    it "terminates it instead of canceling it" do
      expect(result).to be_success
      expect(contract.reload.status).to eq("terminated")
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    it "cancels it instead of terminating" do
      freeze_time do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "canceled", canceled_at: Time.current)
        expect(contract.terminated_at).to be_nil
      end
    end
  end

  context "when the contract is already terminated" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
    end
  end

  context "when the contract is already canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
