# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Analytics::FinalizedInvoicesController, type: :request do # rubocop:disable RSpec/FilePath
  describe 'GET /analytics/s' do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns the gross revenue' do
        get_with_token(
          organization,
          '/api/v1/analytics/finalized_invoices',
        )

        aggregate_failures do
          expect(response).to have_http_status(:success)

          month = DateTime.parse json[:finalized_invoices].first[:month]

          expect(month).to eq(DateTime.current.beginning_of_month)
          expect(json[:finalized_invoices].first[:payment_status]).to eq(nil)
          expect(json[:finalized_invoices].first[:invoices_count]).to eq(0)
          expect(json[:finalized_invoices].first[:amount_cents]).to eq(0.0)
          expect(json[:finalized_invoices].first[:currency]).to eq(nil)
        end
      end
    end

    context 'when licence is not premium' do
      it 'returns forbidden status' do
        get_with_token(
          organization,
          '/api/v1/analytics/finalized_invoices',
        )

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
