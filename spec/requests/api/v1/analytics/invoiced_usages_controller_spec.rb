# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Analytics::InvoicedUsagesController, type: :request do # rubocop:disable RSpec/FilePath
  describe 'GET /analytics/invoiced_usage' do
    subject { get_with_token(organization, '/api/v1/analytics/invoiced_usage') }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context 'when license is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns the invoiced usage' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:invoiced_usages]).to eq([])
        end
      end
    end

    context 'when license is not premium' do
      it 'returns forbidden status' do
        subject
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
