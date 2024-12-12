# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Customers::InvoiceCustomSectionsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        customerInvoiceCustomSections(customerId: $customerId) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 5, organization:) }

  before do
    organization.selected_invoice_custom_sections = invoice_custom_sections.first(3)
    organization.save
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'

  it 'returns a list of invoice_custom_sections' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {customerId: customer.id}
    )

    invoice_cus_secs_response = result['data']['customerInvoiceCustomSections']

    expect(invoice_cus_secs_response['collection'].count).to eq(3)
    expect(invoice_cus_secs_response['collection'].pluck('id')).to contain_exactly(*invoice_custom_sections.first(3).pluck(:id))
    expect(invoice_cus_secs_response['metadata']['currentPage']).to eq(1)
    expect(invoice_cus_secs_response['metadata']['totalCount']).to eq(3)
  end
end
