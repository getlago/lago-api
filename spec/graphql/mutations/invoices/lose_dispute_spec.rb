# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::LoseDispute, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, status: :finalized, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: LoseInvoiceDisputeInput!) {
        loseInvoiceDispute(input: $input) {
          id
          paymentDisputeLostAt
        }
      }
    GQL
  end

  it 'marks payment dispute lost to true' do
    freeze_time do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      result_data = result['data']['loseInvoiceDispute']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['paymentDisputeLostAt']).to be_present
      end
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
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
        current_user: membership.user,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
