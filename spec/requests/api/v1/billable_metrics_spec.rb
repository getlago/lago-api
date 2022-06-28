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
        field_name: 'amount_sum'
      }
    end

    it 'creates a billable_metric' do
      post_with_token(organization, '/api/v1/billable_metrics', { billable_metric: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:billable_metric]
      expect(result[:lago_id]).to be_present
      expect(result[:code]).to eq(create_params[:code])
      expect(result[:name]).to eq(create_params[:name])
      expect(result[:created_at]).to be_present
    end
  end

  describe 'update' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:code) { 'BM1_code' }
    let(:update_params) do
      {
        name: 'BM1',
        code: code,
        description: 'description',
        aggregation_type: 'sum_agg',
        field_name: 'amount_sum'
      }
    end

    it 'updates a billable_metric' do
      put_with_token(organization,
                     "/api/v1/billable_metrics/#{billable_metric.code}",
                     { billable_metric: update_params }
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:billable_metric]

      expect(result[:lago_id]).to eq(billable_metric.id)
      expect(result[:code]).to eq(update_params[:code])
    end

    context 'when billable metric does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/billable_metrics/invalid', { billable_metric: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable metric code already exists in organization scope (validation error)' do
      let(:billable_metric2) { create(:billable_metric, organization: organization) }
      let(:code) { billable_metric2.code }

      before { billable_metric2 }

      it 'returns unprocessable_entity error' do
        put_with_token(organization,
                       "/api/v1/billable_metrics/#{billable_metric.code}",
                       { billable_metric: update_params }
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'show' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    it 'returns a billable metric' do
      get_with_token(
        organization,
        "/api/v1/billable_metrics/#{billable_metric.code}"
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:billable_metric]

      expect(result[:lago_id]).to eq(billable_metric.id)
      expect(result[:code]).to eq(billable_metric.code)
    end

    context 'when billable metric does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/billable_metrics/555"
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    before { billable_metric }

    it 'deletes a billable_metric' do
      expect { delete_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}") }
        .to change(BillableMetric, :count).by(-1)
    end

    it 'returns deleted billable_metric' do
      delete_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:billable_metric]

      expect(result[:lago_id]).to eq(billable_metric.id)
      expect(result[:code]).to eq(billable_metric.code)
    end

    context 'when billable metric does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/billable_metrics/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when billable metric is attached to active subscription' do
      let(:subscription) { create(:subscription) }
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric) }
      let(:billable_metric) { create(:billable_metric, organization: organization) }

      before do
        charge
        subscription
      end

      it 'returns forbidden error' do
        delete_with_token(organization, "/api/v1/billable_metrics/#{billable_metric.code}")

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'index' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    before { billable_metric }

    it 'returns billable metrics' do
      get_with_token(organization, '/api/v1/billable_metrics')

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:billable_metrics]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(billable_metric.id)
      expect(records.first[:code]).to eq(billable_metric.code)
    end

    context 'with pagination' do
      let(:billable_metric2) { create(:billable_metric, organization: organization) }

      before { billable_metric2 }

      it 'returns billable metrics with correct meta data' do
        get_with_token(organization, '/api/v1/billable_metrics?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:billable_metrics].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end
  end
end
