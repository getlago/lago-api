# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::Regenerate, type: :graphql do
  let(:required_permission) { "invoices:void" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, status: :finalized, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: VoidInvoiceInput!) {
        RegenerateInvoice(input: $input) {
          id
          status
        }
      }
    GQL
  end
end
