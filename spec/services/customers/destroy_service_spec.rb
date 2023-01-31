# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::DestroyService, type: :service do
  subject(:customers_service) { described_class.new(customer:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'destroy' do
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:customer) { create(:customer, organization:) }

    before { customer }

    it 'destroys the customer' do
      expect do
        customers_service.call
      end.to change(Customer, :count).by(-1)
    end

    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns an error' do
        result = customers_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when customer is attached to subscription' do
      before do
        create(:subscription, customer:)
      end

      it 'returns an error' do
        result = customers_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq('attached_to_an_active_subscription')
      end
    end
  end
end
