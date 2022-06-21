# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomersService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'update' do
    let(:user) { membership.user }

    let(:customer) { create(:customer, organization: organization) }
    let(:customer_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: 'Updated customer name',
        customer_id: customer_id,
      }
    end

    it 'updates a customer' do
      result = customers_service.update(**update_args)

      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq('Updated customer name')
      end
    end

    context 'with validation error' do
      let(:customer_id) { nil }

      it 'returns an error' do
        result = customers_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'when attached to a subscription' do
      before do
        create(:subscription, customer: customer)
      end

      it 'updates only the name' do
        result = customers_service.update(**update_args)

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.name).to eq('Updated customer name')
          expect(updated_customer.customer_id).to eq(customer.customer_id)
        end
      end
    end

    context 'when updating payment provider' do
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          customer_id: customer_id,
          payment_provider: 'stripe',
        }
      end

      it 'creates a payment provider customer' do
        result = customers_service.update(**update_args)

        expect(result).to be_success

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.payment_provider).to eq('stripe')
          expect(updated_customer.stripe_customer).to be_present
        end
      end
    end
  end

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
        expect(result.error).to eq('not_found')
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
        expect(result.error_code).to eq('forbidden')
      end
    end
  end
end
