# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BillableMetricsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'create' do
    let(:create_params) do
      {
        name: 'BM1',
        code: 'BM1_code',
        description: 'description',
        aggregation_type: 'sum_agg',
        field_name: 'amount_sum',
        recurring: true
      }
    end

    it 'creates a billable_metric' do
      post_with_token(organization, '/api/v1/billable_metrics', {billable_metric: create_params})

      expect(response).to have_http_status(:success)
      expect(json[:billable_metric][:lago_id]).to be_present
      expect(json[:billable_metric][:code]).to eq(create_params[:code])
      expect(json[:billable_metric][:name]).to eq(create_params[:name])
      expect(json[:billable_metric][:created_at]).to be_present
      expect(json[:billable_metric][:recurring]).to eq(create_params[:recurring])
      expect(json[:billable_metric][:filters]).to eq([])
    end

    context 'with weighted sum aggregation' do
      let(:create_params) do
        {
          name: 'BM1',
          code: 'BM1_code',
          description: 'description',
          aggregation_type: 'weighted_sum_agg',
          field_name: 'amount_sum',
          recurring: true,
          weighted_interval: 'seconds'
        }
      end

      it 'creates a billable_metric' do
        post_with_token(organization, '/api/v1/billable_metrics', {billable_metric: create_params})

        expect(response).to have_http_status(:success)
        expect(json[:billable_metric][:lago_id]).to be_present
        expect(json[:billable_metric][:recurring]).to eq(
          create_params[:recurring
                    ]
        )
        expect(json[:billable_metric][:aggregation_type]).to eq('weighted_sum_agg')
        expect(json[:billable_metric][:weighted_interval]).to eq('seconds')
      end
    end
  end

  describe 'update' do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:code) { 'BM1_code' }
    let(:update_params) do
      {
        name: 'BM1',
        code:,
        description: 'description',
        aggregation_type: 'sum_agg',
        field_name: 'amount_sum'
      }
    end

    it 'updates a billable_metric' do
      put_with_token(
        organization,
        "/api/v1/billable_metrics/#{billable_metric.code}",
        {billable_metric: update_params}
      )

      expect(response).to have_http_status(:success)
      expect(json[:billable_metric][:lago_id]).to eq(billable_metric.id)
      expect(json[:billable_metric][:code]).to eq(update_params[:code])
      expect(json[:billable_metric][:filters]).to eq([])
    end

    context 'when billable metric does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/billable_metrics/invalid', {billable_metric: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable metric code already exists in organization scope (validation error)' do
      let(:billable_metric2) { create(:billable_metric, organization:) }
      let(:code) { billable_metric2.code }

      before { billable_metric2 }

      it 'returns unprocessable_entity error' do
        put_with_token(
          organization,
          "/api/v1/billable_metrics/#{billable_metric.code}",
          {billable_metric: update_params}
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with weighted sum aggregation' do
      let(:update_params) do
        {
          name: 'BM1',
          code: 'BM1_code',
          description: 'description',
          aggregation_type: 'weighted_sum_agg',
          field_name: 'amount_sum',
          recurring: true,
          weighted_interval: 'seconds'
        }
      end

      it 'updates a billable_metric' do
        put_with_token(
          organization,
          "/api/v1/billable_metrics/#{billable_metric.code}",
          {billable_metric: update_params}
        )

        expect(response).to have_http_status(:success)
        expect(json[:billable_metric][:lago_id]).to be_present
        expect(json[:billable_metric][:recurring]).to be_truthy
        expect(json[:billable_metric][:aggregation_type]).to eq('weighted_sum_agg')
        expect(json[:billable_metric][:weighted_interval]).to eq('seconds')
      end
    end
  end

  describe 'show' do
    let(:billable_metric) { create(:billable_metric, organization:) }

    it 'returns a billable metric' do
      get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}")

      expect(response).to have_http_status(:success)
      expect(json[:billable_metric][:lago_id]).to eq(billable_metric.id)
      expect(json[:billable_metric][:code]).to eq(billable_metric.code)
    end

    context 'when billable metric does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/billable_metrics/555')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable metric is deleted' do
      it 'returns not found' do
        billable_metric.discard
        get_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:billable_metric) { create(:billable_metric, organization:) }

    before { billable_metric }

    it 'deletes a billable_metric' do
      expect { delete_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}") }
        .to change(BillableMetric, :count).by(-1)
    end

    it 'returns deleted billable_metric' do
      delete_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}")

      expect(response).to have_http_status(:success)
      expect(json[:billable_metric][:lago_id]).to eq(billable_metric.id)
      expect(json[:billable_metric][:code]).to eq(billable_metric.code)
    end

    context 'when billable metric does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/billable_metrics/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:billable_metric) { create(:billable_metric, organization:) }

    before { billable_metric }

    it 'returns billable metrics' do
      get_with_token(organization, '/api/v1/billable_metrics')

      expect(response).to have_http_status(:success)
      expect(json[:billable_metrics].count).to eq(1)
      expect(json[:billable_metrics].first[:lago_id]).to eq(billable_metric.id)
      expect(json[:billable_metrics].first[:code]).to eq(billable_metric.code)
    end

    context 'with pagination' do
      let(:billable_metric2) { create(:billable_metric, organization:) }

      before { billable_metric2 }

      it 'returns billable metrics with correct meta data' do
        get_with_token(organization, '/api/v1/billable_metrics?page=1&per_page=1')

        expect(response).to have_http_status(:success)
        expect(json[:billable_metrics].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
