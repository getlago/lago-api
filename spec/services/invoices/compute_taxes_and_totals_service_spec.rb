# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ComputeTaxesAndTotalsService, type: :service do
  subject(:totals_service) { described_class.new(invoice:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:invoice) do
      create(
        :invoice,
        :finalized,
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

    context "when there is tax provider" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

      before do
        integration_customer
      end

      it "enqueues a Invoices::ProviderTaxes::PullTaxesAndApplyJob" do
        expect do
          totals_service.call
        end.to have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob).with(invoice:)
      end

      it "sets correct statuses on invoice" do
        totals_service.call

        expect(invoice.reload.status).to eq("pending")
        expect(invoice.reload.tax_status).to eq("pending")
      end

      context "when invoice is draft" do
        before { invoice.update!(status: :draft) }

        it "sets only tax status" do
          described_class.new(invoice:, finalizing: false).call

          expect(invoice.reload.status).to eq("draft")
          expect(invoice.reload.tax_status).to eq("pending")
        end
      end

      context "when there is no fees" do
        let(:fee_subscription) { nil }
        let(:fee_charge) { nil }
        let(:result) { BaseService::Result.new }

        before do
          allow(Invoices::ComputeAmountsFromFees).to receive(:call)
            .with(invoice:)
            .and_return(result)
        end

        it "skips tax provider flow" do
          totals_service.call

          expect(Invoices::ComputeAmountsFromFees).to have_received(:call)
        end
      end
    end

    context "when there is NO tax provider" do
      let(:result) { BaseService::Result.new }

      before do
        allow(Invoices::ComputeAmountsFromFees).to receive(:call)
          .with(invoice:)
          .and_return(result)
      end

      it "calls the add on create service" do
        totals_service.call

        expect(Invoices::ComputeAmountsFromFees).to have_received(:call)
      end
    end
  end
end
