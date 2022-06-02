# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Customers::ForecastResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        forecast(customerId: $customerId) {
          fromDate,
          toDate,
          issuingDate,
          amountCents,
          amountCurrency,
          totalAmountCents,
          totalAmountCurrency,
          vatAmountCents,
          vatAmountCurrency,
          fees {
            billableMetricName,
            billableMetricCode,
            aggregationType,
            chargeModel,
            units,
            amountCents,
            amountCurrency,
            vatAmountCents,
            vatAmountCurrency
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      customer: customer,
      started_at: Time.zone.now - 2.years,
    )
  end
  let(:plan) { create(:plan, interval: 'monthly') }

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :graduated_charge,
      plan: subscription.plan,
      charge_model: 'graduated',
      billable_metric: billable_metric,
      properties: [
        {
          from_value: 0,
          to_value: nil,
          per_unit_amount: '0.01',
          flat_amount: '0.01',
        },
      ],
    )
  end

  before do
    subscription
    charge

    create_list(
      :event,
      4,
      organization: organization,
      customer: customer,
      code: billable_metric.code,
      timestamp: Time.zone.now,
    )
  end

  it 'returns the forecast for the customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        customerId: customer.id,
      },
    )

    forecast_response = result['data']['forecast']

    aggregate_failures do
      expect(forecast_response['fromDate']).to eq(Time.zone.today.beginning_of_month.iso8601)
      expect(forecast_response['toDate']).to eq(Time.zone.today.end_of_month.iso8601)
      expect(forecast_response['issuingDate']).to eq(Time.zone.today.end_of_month.iso8601)
      expect(forecast_response['amountCents']).to eq(5)
      expect(forecast_response['amountCurrency']).to eq('EUR')
      expect(forecast_response['totalAmountCents']).to eq(6)
      expect(forecast_response['totalAmountCurrency']).to eq('EUR')
      expect(forecast_response['vatAmountCents']).to eq(1)
      expect(forecast_response['vatAmountCurrency']).to eq('EUR')

      fee_response = forecast_response['fees'].first
      expect(fee_response['billableMetricName']).to eq(billable_metric.name)
      expect(fee_response['billableMetricCode']).to eq(billable_metric.code)
      expect(fee_response['aggregationType']).to eq('count_agg')
      expect(fee_response['chargeModel']).to eq('graduated')
      expect(fee_response['units']).to eq(4)
      expect(fee_response['amountCents']).to eq(5)
      expect(fee_response['amountCurrency']).to eq('EUR')
      expect(fee_response['vatAmountCents']).to eq(1)
      expect(fee_response['vatAmountCurrency']).to eq('EUR')
    end
  end
end
