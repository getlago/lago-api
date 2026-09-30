# frozen_string_literal: true

require "rails_helper"

describe BillingSegments::ScheduleJob, job: true do
  subject { described_class }

  let(:customer) { create(:customer) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe "unique" do
    it "releases its lock once it starts, so a request made during a run is not dropped" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
    end
  end

  describe ".perform" do
    before do
      allow(BillingSegments::ScheduleService).to receive(:call!).and_return(BillingSegments::ScheduleService::Result.new)
    end

    it "schedules the customer's due segments" do
      described_class.perform_now(customer.id)

      expect(BillingSegments::ScheduleService).to have_received(:call!).with(customer:)
    end

    it "does not invoice when nothing awaits invoicing" do
      described_class.perform_now(customer.id)

      expect(BillingSegments::ProcessJob).not_to have_been_enqueued
    end

    context "when a segment awaits invoicing" do
      before { create(:billing_segment, customer:, organization: customer.organization) }

      it "invoices it right away" do
        described_class.perform_now(customer.id)

        expect(BillingSegments::ProcessJob).to have_been_enqueued.with(customer.id)
      end
    end

    context "when the only segment is metered usage billed in advance" do
      let(:rate_card) { create(:rate_card, :advance, organization: customer.organization) }
      let(:contract) { create(:contract, organization: customer.organization, customer:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization: customer.organization, contract:, rate_card:) }

      before do
        create(:billing_segment, customer:, organization: customer.organization, contract:, contract_rate_card:, status: :processing)
      end

      it "does not invoice it" do
        described_class.perform_now(customer.id)

        expect(BillingSegments::ProcessJob).not_to have_been_enqueued
      end
    end
  end
end
