# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::InitFromAdjustedChargeFeeService, type: :service do
  subject(:init_service) { described_class.new(adjusted_fee:, boundaries:, properties:) }

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: DateTime.parse('2022-03-15'),
    )
  end

  let(:invoice) { create(:invoice, status: :draft) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric:,
      properties: {
        amount: '20',
        amount_currency: 'EUR'
      },
    )
  end
  let(:properties) { charge.properties }

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day
    }
  end

  let(:adjusted_fee) do
    create(
      :adjusted_fee,
      invoice:,
      subscription:,
      charge:,
      properties: {},
      fee_type: :charge,
      adjusted_units: true,
      adjusted_amount: false,
      units: 3,
    )
  end

  before do
    invoice_subscription
  end

  context 'with adjusted units' do
    it 'initializes a fee' do
      result = init_service.call

      expect(result).to be_success
      expect(result.fee).to be_a(Fee)
      expect(result.fee).to have_attributes(
        id: nil,
        invoice:,
        subscription:,
        charge:,
        amount_cents: 6_000,
        amount_currency: invoice.currency,
        units: 3,
        unit_amount_cents: 2_000,
        precise_unit_amount: 20,
        events_count: 0,
        payment_status: 'pending',
      )
    end
  end

  context 'with adjusted amount' do
    let(:adjusted_fee) do
      create(
        :adjusted_fee,
        invoice:,
        subscription:,
        charge:,
        properties:,
        fee_type: :charge,
        adjusted_units: false,
        adjusted_amount: true,
        units: 4,
        unit_amount_cents: 200,
      )
    end

    it 'initializes a fee' do
      result = init_service.call

      expect(result).to be_success
      expect(result.fee).to be_a(Fee)
      expect(result.fee).to have_attributes(
        id: nil,
        invoice:,
        charge:,
        amount_cents: 800,
        amount_currency: invoice.currency,
        units: 4,
        unit_amount_cents: 200,
        precise_unit_amount: 2,
        events_count: 0,
        payment_status: 'pending',
      )
    end
  end

  context 'with charge model error' do
    let(:error_result) do
      BaseService::Result.new.tap do |result|
        result.service_failure!(code: 'error', message: 'message')
      end
    end

    let(:charge_model_instance) { instance_double(Charges::ChargeModels::StandardService) }

    it 'returns an error' do
      allow(Charges::ChargeModels::StandardService).to receive(:new).and_return(charge_model_instance)
      allow(charge_model_instance).to receive(:apply).and_return(error_result)

      result = init_service.call
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq('error')
      expect(result.error.error_message).to eq('message')
    end
  end
end
