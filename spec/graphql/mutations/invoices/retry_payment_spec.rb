# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::RetryPayment, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization, payment_provider: 'gocardless') }
  let(:gocardless_payment_provider) { create(:gocardless_provider, organization: organization) }
  let(:gocardless_customer) { create(:gocardless_customer, customer: customer) }
  let(:user) { membership.user }
  let(:invoice) do
    create(
      :invoice,
      customer: customer,
      status: 'finalized',
      payment_status: 'failed',
      ready_for_payment_processing: true,
    )
  end
  let(:mutation) do
    <<-GQL
      mutation($input: RetryPaymentInput!) {
        retryPayment(input: $input) {
          id
          paymentStatus
        }
      }
    GQL
  end

  context 'with valid preconditions' do
    it 'returns the invoice after payment retry' do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      data = result['data']['retryPayment']

      expect(data['id']).to eq(invoice.id)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: user,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
