# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::InvoicedUsagesService, type: :service do
  let(:service) { described_class.new(organization) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  describe '#call' do
    subject(:service_call) { service.call }

    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns success' do
        expect(service_call).to be_success
      end
    end

    context 'when licence is not premium' do
      it 'returns an error' do
        aggregate_failures do
          expect(service_call).not_to be_success
          expect(service_call.error.code).to eq('feature_unavailable')
        end
      end
    end
  end
end
