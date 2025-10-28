# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::EstimatePayInAdvanceService do
  subject(:estimate_service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:) }

  let(:customer) { create(:customer, organization:) }

  let(:subscription) do
    create(
      :subscription,
      customer:,
      plan:,
      started_at: 1.year.ago
    )
  end

  let(:params) do
    {
      code:,
      external_customer_id:,
      external_subscription_id:
    }
  end

  let(:code) { billable_metric&.code }
  let(:external_customer_id) { customer&.external_id }
  let(:external_subscription_id) { subscription&.external_id }

  before { charge }

  describe "#call" do
    it "does not persist any events" do
      expect { estimate_service.call }.not_to change(Event, :count)
    end

    it "returns a list of fees" do
      result = estimate_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.fees.count).to eq(1)

        fee = result.fees.first
        expect(fee).not_to be_persisted
        expect(fee).to have_attributes(
          subscription:,
          charge:,
          fee_type: "charge",
          pay_in_advance: true,
          invoiceable: charge,
          events_count: 1,
          pay_in_advance_event_id: nil,
          pay_in_advance_event_transaction_id: String
        )
      end
    end

    context "when charge model is dynamic" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
      let(:charge) { create(:dynamic_charge, :pay_in_advance, plan:, billable_metric:) }

      let(:params) do
        {
          code:,
          external_customer_id:,
          external_subscription_id:,
          properties: {billable_metric.field_name => 10},
          precise_total_amount_cents: 120_00
        }
      end

      it "returns a list of fees" do
        result = estimate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.fees.count).to eq(1)

          fee = result.fees.first
          expect(fee).not_to be_persisted
          expect(fee).to have_attributes(
            subscription:,
            charge:,
            fee_type: "charge",
            pay_in_advance: true,
            invoiceable: charge,
            events_count: 1,
            pay_in_advance_event_id: nil,
            pay_in_advance_event_transaction_id: String,
            amount_cents: 120_00
          )
        end
      end
    end

    context "when event code does not match an pay_in_advance charge" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }

      it "fails with a validation error" do
        result = estimate_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(["does_not_match_an_instant_charge"])
        end
      end
    end

    context "when event matches multiple charges" do
      let(:charge2) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:) }

      before { charge2 }

      it "returns a fee per charges" do
        result = estimate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.fees.count).to eq(2)
        end
      end
    end

    context "when external customer is not found" do
      let(:params) do
        {code:, external_customer_id: "unknown"}
      end

      it "fails with a not found error" do
        result = estimate_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("subscription_not_found")
        end
      end
    end

    context "when external subscription is not found" do
      let(:external_subscription_id) { nil }

      it "fails with a not found error" do
        result = estimate_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("subscription_not_found")
        end
      end

      context "when customer has an active subscription" do
        let(:subscription) do
          create(
            :subscription,
            customer:,
            plan:,
            started_at: 1.year.ago
          )
        end

        before { subscription }

        it "returns nothing" do
          result = estimate_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.fees).to be_nil
          end
        end
      end
    end
  end
end
