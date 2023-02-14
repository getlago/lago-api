# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateInvoiceInput!) {
        updateInvoice(input: $input) {
          id
          paymentStatus
        }
      }
    GQL
  end

  it 'updates a invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          id: invoice.id,
          paymentStatus: 'succeeded',
        },
      },
    )

    result_data = result['data']['updateInvoice']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['paymentStatus']).to eq('succeeded')
    end
  end

  context 'when invoice does not exists' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            id: '1234',
            paymentStatus: 'succeeded',
          },
        },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        current_organization: organization,
        variables: {
          input: {
            id: invoice.id,
            paymentStatus: 'succeeded',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
