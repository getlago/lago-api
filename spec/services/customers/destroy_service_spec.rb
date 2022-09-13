# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::DestroyService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'destroy' do
    subject(:customers_service) { described_class.new(membership.user) }

    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:customer) { create(:customer, organization: organization) }

    it 'destroys the customer' do
      id = customer.id

      expect do
        customers_service.destroy(
          id: id,
        )
      end.to change(Customer, :count).by(-1)
    end

    context 'when customer is not found' do
      it 'returns an error' do
        result = customers_service.destroy(
          id: nil,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when customer is attached to subscription' do
      before do
        create(:subscription, customer: customer)
      end

      it 'returns an error' do
        result = customers_service.destroy(
          id: customer.id,
        )

        expect(result).not_to be_success
        expect(result.error.code).to eq('attached_to_an_active_subscription')
      end
    end
  end
end
