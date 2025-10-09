# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RetryService do
  subject(:retry_service) { described_class.new(invoice:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(
        :invoice,
        :failed,
        :with_tax_error,
        :subscription,
        customer:,
        organization:,
        subscriptions: [subscription],
        currency: "EUR",
        issuing_date: Time.zone.at(timestamp).to_date
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end

    let(:timestamp) { Time.zone.now - 1.year }
    let(:started_at) { Time.zone.now - 2.years }
    let(:plan) { create(:plan, organization:, interval: "monthly") }
    let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
    let(:charge) { create(:standard_charge, plan: subscription.plan, charge_model: "standard", billable_metric:) }

    let(:fee_subscription) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 2_000
      )
    end
    let(:fee_charge) do
      create(
        :fee,
        invoice:,
        charge:,
        fee_type: :charge,
        total_aggregated_units: 100,
        amount_cents: 1_000
      )
    end

    before do
      fee_subscription
      fee_charge
    end

    context "when invoice does not exist" do
      it "returns an error" do
        result = described_class.new(invoice: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invoice_not_found")
      end
    end

    context "when invoice is not failed" do
      before do
        invoice.update(status: %i[draft finalized voided generating].sample)
      end

      it "returns an error" do
        result = retry_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("invalid_status")
      end
    end

    it "enqueues a Invoices::ProviderTaxes::PullTaxesAndApplyJob" do
      expect do
        retry_service.call
      end.to have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob).with(invoice:)
    end

    it "sets correct statuses" do
      retry_service.call

      expect(invoice.reload.status).to eq("pending")
      expect(invoice.reload.tax_status).to eq("pending")
    end
  end
end
