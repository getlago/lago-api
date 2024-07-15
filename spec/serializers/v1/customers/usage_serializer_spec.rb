# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Customers::UsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: 'customer_usage', includes: [:charges_usage]) }

  let(:usage) do
    OpenStruct.new(
      from_datetime: Time.current.beginning_of_month.iso8601,
      to_datetime: Time.current.end_of_month.iso8601,
      issuing_date: Time.current.end_of_month.iso8601,
      amount_cents: 5,
      currency: 'EUR',
      total_amount_cents: 6,
      taxes_amount_cents: 1,
      fees: [
        OpenStruct.new(
          billable_metric: OpenStruct.new(
            id: SecureRandom.uuid,
            name: 'Charge',
            code: 'charge',
            aggregation_type: 'count_agg'
          ),
          charge: OpenStruct.new(
            id: SecureRandom.uuid,
            charge_model: 'graduated'
          ),
          units: '4.0',
          amount_cents: 5,
          amount_currency: 'EUR',
          groups: []
        )
      ]
    )
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the customer usage' do
    aggregate_failures do
      expect(result['customer_usage']['from_datetime']).to eq(Time.current.beginning_of_month.iso8601)
      expect(result['customer_usage']['to_datetime']).to eq(Time.current.end_of_month.iso8601)
      expect(result['customer_usage']['issuing_date']).to eq(Time.current.end_of_month.iso8601)
      expect(result['customer_usage']['currency']).to eq('EUR')
      expect(result['customer_usage']['taxes_amount_cents']).to eq(1)
      expect(result['customer_usage']['amount_cents']).to eq(5)
      expect(result['customer_usage']['total_amount_cents']).to eq(6)

      charge_usage = result['customer_usage']['charges_usage'].first
      expect(charge_usage['billable_metric']['name']).to eq('Charge')
      expect(charge_usage['billable_metric']['code']).to eq('charge')
      expect(charge_usage['billable_metric']['aggregation_type']).to eq('count_agg')
      expect(charge_usage['charge']['charge_model']).to eq('graduated')
      expect(charge_usage['units']).to eq('4.0')
      expect(charge_usage['amount_cents']).to eq(5)
      expect(charge_usage['amount_currency']).to eq('EUR')
      expect(charge_usage['groups']).to eq([])
    end
  end
end
