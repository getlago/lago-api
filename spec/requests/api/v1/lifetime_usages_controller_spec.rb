# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::LifetimeUsagesController, type: :request do
  let(:lifetime_usage) { create(:lifetime_usage, organization:, subscription:) }
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:, subscription_at:) }
  let(:subscription_at) { Date.new(2022, 8, 22) }

  before { lifetime_usage }

  describe 'show' do
    it 'returns the lifetime_usage' do
      get_with_token(
        organization,
        "/api/v1/subscriptions/#{subscription.external_id}/lifetime_usage"
      )

      expect(response).to have_http_status(:success)
      expect(json[:lifetime_usage][:lago_id]).to eq(lifetime_usage.id)
    end

    context 'when subscription cannot be found' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/subscriptions/123/lifetime_usage')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'update' do
    let(:update_params) { {external_historical_usage_amount_cents: 20} }

    it 'updates the lifetime_usage' do
      put_with_token(
        organization,
        "/api/v1/subscriptions/#{subscription.external_id}/lifetime_usage",
        {lifetime_usage: update_params}
      )

      expect(response).to have_http_status(:success)
      expect(json[:lifetime_usage][:lago_id]).to eq(lifetime_usage.id)
      expect(json[:lifetime_usage][:external_historical_usage_amount_cents]).to eq(20)
    end

    context 'when subscription cannot be found' do
      it 'returns not found' do
        put_with_token(organization, '/api/v1/subscriptions/123/lifetime_usage', {lifetime_usage: update_params})
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
