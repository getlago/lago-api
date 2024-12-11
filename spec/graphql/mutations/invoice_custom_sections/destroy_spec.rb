# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::InvoiceCustomSections::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyInvoiceCustomSectionInput!) {
        destroyInvoiceCustomSection(input: $input) { id }
      }
    GQL
  end

  before { invoice_custom_section }

  it 'destroys am invoice_custom_section' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {input: {id: invoice_custom_section.id}}
      )
    end.to change(InvoiceCustomSection, :count).by(-1)
  end
end
