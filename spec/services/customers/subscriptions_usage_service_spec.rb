# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::SubscriptionsUsageService do
  describe "#call" do
    subject(:result) { described_class.call(customer:, include_generating_invoices:) }

    let(:include_generating_invoices) { false }
    let(:customer) { create(:customer) }
    let(:organization) { customer.organization }
    let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
    let(:pay_in_advance_billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }

    let(:subscriptions) do
      [
        create(:subscription, organization:, customer:, started_at: Time.zone.now - 2.years),
        create(:subscription, organization:, customer:, started_at: Time.zone.now - 1.year)
      ]
    end

    before do
      subscriptions.each do |subscription|
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {amount: "3"}
        )

        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: pay_in_advance_billable_metric,
          properties: {amount: "1"},
          pay_in_advance: true,
          invoiceable: true
        )
      end

      create_pair(
        :event,
        organization:,
        subscription: subscriptions.first,
        customer:,
        code: billable_metric.code
      )

      create(
        :event,
        organization:,
        subscription: subscriptions.second,
        customer:,
        code: billable_metric.code
      )

      create(
        :event,
        organization:,
        subscription: subscriptions.second,
        customer:,
        code: pay_in_advance_billable_metric.code
      )
    end

    it "returns aggregated usage amounts" do
      expect(result).to be_success
      expect(result.billed_usage_amount_cents).to eq(100)
    end

    it "returns fees from all subscriptions" do
      expect(result.fees).to be_present
      expect(result.fees.size).to eq(4) # 2 charges per subscription
    end

    context "with progressive billing invoices" do
      let(:charges_to_datetime) { 1.week.from_now }
      let(:charges_from_datetime) { 1.week.ago }

      before do
        subscriptions.each do |subscription|
          create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) do |invoice_subscription|
            create(
              :charge_fee,
              subscription:,
              precise_coupons_amount_cents: 0,
              invoice: invoice_subscription.invoice,
              amount_cents: 100,
              taxes_amount_cents: 10
            )

            invoice_subscription.invoice.update!(
              invoice_type: :progressive_billing,
              fees_amount_cents: 110,
              total_amount_cents: 110,
              status: :generating
            )
          end
        end
      end

      context "when generating invoices are included" do
        let(:include_generating_invoices) { true }

        it "includes generating invoices in billed amount" do
          expect(result.billed_usage_amount_cents).to eq(320)
        end
      end

      context "when generating invoices are excluded" do
        let(:include_generating_invoices) { false }

        it "excludes generating invoices from billed amount" do
          expect(result.billed_usage_amount_cents).to eq(100)
        end
      end
    end

    context "when customer has no active subscriptions" do
      it "returns zero amounts and empty fees" do
        customer_without_subscriptions = create(:customer)
        result = described_class.call(customer: customer_without_subscriptions)

        expect(result).to be_success
        expect(result.fees).to be_empty
        expect(result.billed_usage_amount_cents).to eq(0)
      end
    end

    context "when CustomerUsageService fails" do
      before do
        create(:anrok_customer, customer:)

        allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService)
          .to receive(:call)
          .and_return(
            BaseService::Result.new.service_failure!(
              code: "customerAddressCouldNotResolve",
              message: "Customer address could not resolve"
            )
          )
      end

      it "returns the failure result" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:tax_error]).to eq(["customerAddressCouldNotResolve"])
      end
    end
  end
end
