# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CustomerPortal::DownloadInvoice, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DownloadCustomerPortalInvoiceInput!) {
        downloadCustomerPortalInvoice(input: $input) {
          id
        }
      }
    GQL
  end

  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }

  let(:pdf_response) do
    BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
  end

  let(:pdf_content) do
    File.read(Rails.root.join('spec/fixtures/blank.pdf'))
  end

  before do
    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_response)
  end

  it_behaves_like 'requires a customer portal user'

  it 'generates the PDF for the given invoice' do
    freeze_time do
      result = execute_graphql(
        customer_portal_user: customer,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      result_data = result['data']['downloadCustomerPortalInvoice']

      aggregate_failures do
        expect(result_data['id']).to eq(invoice.id)
      end
    end
  end

  context 'without customer portal user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
