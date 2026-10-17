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
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current, ended_at: Time.current)
      expect(contract.canceled_at).to be_nil
    end
  end

  context "when the contract bills rate cards" do
    let(:timezone) { Time.find_zone("America/Los_Angeles") }
    let(:customer) { create(:customer, organization:, timezone: timezone.name) }
    let(:started_at) { timezone.parse("2026-08-01 00:00:00") }
    let(:terminated_at) { timezone.parse("2026-08-21 14:00:00") }
    let(:ended_at) { nil }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:, ended_at:) }
    let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }

    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 8, 1), billing_anchor_date: Date.new(2026, 8, 1),
        next_billing_at: timezone.parse("2026-09-01 00:00:00"))
    end

    around { |example| travel_to(terminated_at) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at)
      contract_rate_card
    end

    it "bills the arrears card for the days served, the termination day included" do
      expect(result).to be_success
      expect(BillingSegment.where(contract:).sole).to have_attributes(
        started_at:,
        ended_at: BillingSegment.inclusive_end(terminated_at),
        billing_at: terminated_at,
        # 21 of August's 31 days, though the card does not prorate.
        proration_ratio: BigDecimal("0.6774193548"),
        status: "pending"
      )
    end

    it "stops the card's clock" do
      expect { result }.to change { contract_rate_card.reload.next_billing_at }.to(nil)
    end

    it "invoices the closing period" do
      expect { result }.to have_enqueued_job_after_commit(BillingSegments::ProcessJob).with(customer.id)
    end

    context "when the contract had a later planned end" do
      let(:ended_at) { timezone.parse("2026-12-31 00:00:00") }

      it "brings the end in to the termination" do
        expect { result }.to change { contract.reload.ended_at }.to(terminated_at)
      end
    end

    context "when the planned end already passed" do
      let(:ended_at) { timezone.parse("2026-08-15 00:00:00") }

      it "keeps that end and bills up to it" do
        expect(result).to be_success
        expect(contract.reload.ended_at).to eq(ended_at)
        expect(BillingSegment.where(contract:).sole).to have_attributes(started_at:, billing_at: ended_at)
      end
    end

    context "when the card bills in advance" do
      let(:rate_card) { create(:rate_card, :advance, organization:, proration: false) }

      before do
        contract_rate_card.update!(next_billing_at: started_at)
        BillingSegments::ScheduleService.call!(customer:, timestamp: started_at + 12.minutes)
      end

      it "bills nothing more for the cycle already billed" do
        expect { result }.not_to change(BillingSegment, :count)
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end

      it "does not invoice" do
        expect { result }.not_to have_enqueued_job(BillingSegments::ProcessJob)
      end
    end

    context "when the closing segments cannot be written" do
      let(:failed_result) do
        BaseResult.new.tap { it.single_validation_failure!(field: :billing_segment, error_code: "overlapping_periods") }
      end

      before do
        allow(BillingSegments::ScheduleService).to receive(:call!).and_raise(failed_result.error)
      end

      it "leaves the contract active" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(billing_segment: ["overlapping_periods"])
        expect(contract.reload).to have_attributes(status: "active", terminated_at: nil, ended_at: nil)
      end
    end
  end

  context "when the clock activated the contract since it was loaded" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, started_at: 1.minute.ago) }

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
