# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::EstimateInstantPayInAdvanceService do
  subject { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:percentage_charge, :pay_in_advance, plan:, billable_metric:, properties: {rate: '0.1', fixed_amount: '0'}) }

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
      organization_id:,
      code:,
      external_customer_id:,
      external_subscription_id:,
      timestamp:,
      properties:
    }
  end

  let(:properties) { nil }

  let(:code) { billable_metric&.code }
  let(:external_customer_id) { customer&.external_id }
  let(:external_subscription_id) { subscription&.external_id }
  let(:organization_id) { organization.id }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:currency) { subscription.plan.amount.currency }

  before { charge }

  describe '#call' do
    it 'returns a list of fees' do
      result = subject.call

      expect(result).to be_success
      expect(result.fees.count).to eq(1)

      fee = result.fees.first
      expect(fee).not_to be_persisted
      expect(fee).to have_attributes(
        subscription:,
        charge:,
        fee_type: 'charge',
        pay_in_advance: true,
        invoiceable: charge,
        events_count: 1,
        pay_in_advance_event_id: nil,
        pay_in_advance_event_transaction_id: nil
      )
    end

    context 'when setting event properties' do
      let(:properties) { {billable_metric.field_name => 500} }

      it 'calculates the fee correctly' do
        result = subject.call

        expect(result).to be_success
        expect(result.fees.count).to eq(1)

        fee = result.fees.first
        expect(fee.amount_cents).to eq(50)
      end
    end

    context 'when event code does not match an pay_in_advance charge' do
      let(:charge) { create(:percentage_charge, plan:, billable_metric:) }

      it 'fails with a validation error' do
        result = subject.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(['does_not_match_an_instant_charge'])
        end
      end
    end

    context 'when event matches multiple charges' do
      let(:charge2) { create(:percentage_charge, :pay_in_advance, plan:, billable_metric:) }

      before { charge2 }

      it 'returns a fee per charges' do
        result = subject.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.fees.count).to eq(2)
        end
      end
    end

    context 'when external subscription is not found' do
      let(:external_subscription_id) { nil }

      it 'fails with a not found error' do
        result = subject.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('subscription_not_found')
        end
      end
    end
  end
end
