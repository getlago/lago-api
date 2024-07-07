# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::DataExports::Invoices::Create, type: :graphql do
  let(:required_permission) { 'invoices:export' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:currency) { 'EUR' }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateDataExportsInvoicesInput!) {
        createInvoicesDataExport(input: $input) {
          id,
          status,
       }
      }
    GQL
  end

  before { membership }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'invoices:export'

  it 'creates data export' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          format: 'csv',
          resourceType: 'invoices',
          filters: {
            currency: 'USD',
            customerExternalId: 'abc123',
            invoiceType: 'one_off',
            issuingDateFrom: '2024-05-23',
            issuingDateTo: '2024-07-01',
            paymentDisputeLost: false,
            paymentOverdue: true,
            paymentStatus: 'pending',
            searchTerm: 'service ABC',
            status: 'finalized'
          }
        }
      }
    )

    result_data = result['data']['createInvoicesDataExport']

    aggregate_failures do
      expect(result_data).to include(
        'id' => String,
        'status' => "pending"
      )
    end
  end
end
