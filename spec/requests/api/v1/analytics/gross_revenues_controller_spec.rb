# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Analytics::GrossRevenuesController, type: :request do
  describe 'GET /analytics/gross_revenue' do
    subject { get_with_token(organization, '/api/v1/analytics/gross_revenue') }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns the gross revenue' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:gross_revenues]).to eq([])
        end
      end
    end

    context 'when licence is not premium' do
      it 'returns the gross revenue' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:gross_revenues]).to eq([])
      end
    end
  end
end
