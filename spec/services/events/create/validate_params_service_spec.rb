# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Create::ValidateParamsService, type: :service do
  subject(:service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:metric) do
    create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'amount')
  end

  let(:properties) { { amount: 3 } }
  let(:params) do
    {
      transaction_id: SecureRandom.uuid,
      external_customer_id: SecureRandom.uuid,
      code: metric.code,
      properties:,
    }
  end

  describe '#call' do
    it 'does not return any errors' do
      expect(service.call).to eq({})
    end

    context 'when missing or nil arguments' do
      let(:params) do
        {
          external_customer_id: SecureRandom.uuid,
          code: nil,
        }
      end

      it 'returns an error on these fields' do
        expect(service.call).to eq(
          {
            transaction_id: ['value_is_mandatory'],
            code: ['value_is_mandatory'],
          },
        )
      end
    end

    context 'when metric is not found' do
      it 'returns an error on code' do
        params[:code] = 'unknown'
        expect(service.call).to eq({ code: ['metric_not_found'] })
      end
    end

    context 'when external_customer_id and subscription_id but multiple subscriptions' do
      let(:subscription) { create(:subscription, customer:) }

      before { create(:subscription, customer:) }

      it 'does not return any errors' do
        params[:external_customer_id] = customer.external_id
        params[:external_subscription_id] = subscription.external_id

        expect(service.call).to eq({})
      end
    end

    context 'when only external_customer_id but multiple subscriptions' do
      before { create_list(:subscription, 2, customer:) }

      it 'returns an error on external_subscription_id' do
        params[:external_customer_id] = customer.external_id

        expect(service.call).to eq({ external_subscription_id: ['value_is_mandatory'] })
      end
    end

    context 'when property is a string representing a valid number' do
      let(:properties) { { amount: '3' } }

      it 'does not return any errors' do
        expect(service.call).to eq({})
      end
    end

    context 'when property is not a valid number' do
      let(:properties) { { amount: 'not_a_number' } }

      it 'returns an error on field name for sum_agg' do
        expect(service.call).to eq({ amount: ['value_is_not_valid_number'] })
      end

      it 'returns an error on field name for max_agg' do
        metric.update(aggregation_type: 'max_agg')
        expect(service.call).to eq({ amount: ['value_is_not_valid_number'] })
      end

      it 'does not return any errors when another agg type' do
        metric.update(aggregation_type: 'count_agg')
        expect(service.call).to eq({})
      end
    end
  end
end
