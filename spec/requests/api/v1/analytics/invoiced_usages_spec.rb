# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Analytics::InvoicedUsagesController, type: :request do # rubocop:disable RSpec/FilePath
  describe 'GET /analytics/invoiced_usages' do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context 'when license is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns the invoiced usage' do
        get_with_token(
          organization,
          '/api/v1/analytics/invoiced_usages',
        )

        aggregate_failures do
          expect(response).to have_http_status(:success)

          month = DateTime.parse json[:invoiced_usages].first[:month]

          expect(month).to eq(DateTime.current.beginning_of_month)
          expect(json[:invoiced_usages].first[:code]).to eq(nil)
          expect(json[:invoiced_usages].first[:currency]).to eq(nil)
          expect(json[:invoiced_usages].first[:amount_cents]).to eq(0.0)
        end
      end
    end

    context 'when license is not premium' do
      it 'returns forbidden status' do
        get_with_token(
          organization,
          '/api/v1/analytics/invoiced_usages',
        )

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
