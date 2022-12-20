# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::RetryPayment, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization, payment_provider: 'gocardless') }
  let(:gocardless_payment_provider) { create(:gocardless_provider, organization: organization) }
  let(:gocardless_customer) { create(:gocardless_customer, customer: customer) }
  let(:user) { membership.user }

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

  describe 'retry payment mutation' do
    before do
      gocardless_payment_provider
      gocardless_customer
    end

    context 'with valid preconditions' do
      let(:invoice) do
        create(
          :invoice,
          customer: customer,
          payment_status: 'failed',
          ready_for_payment_processing: true,
        )
      end

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
  end
end
