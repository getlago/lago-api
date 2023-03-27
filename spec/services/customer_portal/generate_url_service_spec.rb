# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerPortal::GenerateUrlService, type: :service do
  subject(:generate_url_service) { described_class.new(customer:) }

  let(:customer) { create(:customer) }

  describe '#call' do
    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'generates valid customer portal url' do
        result = generate_url_service.call

        message = result.url.split('/customer-portal/')[1]
        public_authenticator = ActiveSupport::MessageVerifier.new(ENV['SECRET_KEY_BASE'])

        aggregate_failures do
          expect(result.url).to include('/customer-portal/')
          expect(public_authenticator.verify(message)).to eq(customer.id)
        end
      end

      context 'when customer does not exist' do
        let(:customer) { nil }

        it 'returns an error' do
          result = generate_url_service.call

          expect(result).not_to be_success
          expect(result.error.error_code).to eq('customer_not_found')
        end
      end
    end

    context 'when licence is not premium' do
      it 'returns an error' do
        result = generate_url_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq('feature_unavailable')
      end
    end
  end
end
