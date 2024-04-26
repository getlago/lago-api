# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::Refresh, type: :graphql do
  let(:required_permission) { 'invoices:update' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: RefreshInvoiceInput!) {
        refreshInvoice(input: $input) {
          id
          updatedAt
        }
      }
    GQL
  end

  it_behaves_like 'requires permission', 'invoices:update'

  it 'refreshes the given invoice' do
    freeze_time do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      result_data = result['data']['refreshInvoice']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['updatedAt']).to eq(Time.current.iso8601)
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
        permissions: required_permission,
        query: mutation,
        variables: {
          input: { id: invoice.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
