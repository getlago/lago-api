# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CustomerPortal::DownloadInvoiceXml, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DownloadCustomerPortalInvoiceXmlInput!) {
        downloadCustomerPortalInvoiceXml(input: $input) {
          id
        }
      }
    GQL
  end

  it_behaves_like "requires a customer portal user"

  it "generates the XML for the given invoice" do
    freeze_time do
      result = execute_graphql(
        customer_portal_user: customer,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      result_data = result["data"]["downloadCustomerPortalInvoiceXml"]

      aggregate_failures do
        expect(result_data["id"]).to eq(invoice.id)
      end
    end
  end

  context "without customer portal user" do
    it "returns an error" do
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
