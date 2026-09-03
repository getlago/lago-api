# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentReceipts::DownloadXml do
  let(:required_permission) { "invoices:view" }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:payment) { create(:payment, payable: invoice, customer:) }
  let(:payment_receipt) { create(:payment_receipt, payment:, organization:, billing_entity:) }
  let(:mutation) do
    <<~GQL
      mutation($input: DownloadXMLPaymentReceiptInput!) {
        downloadXmlPaymentReceipt(input: $input) {
          id
          xmlUrl
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:billing_entity) { create_default(:billing_entity, country: "FR", einvoicing: true) }
  let_it_be(:customer) { create_default(:customer, organization:, billing_entity:) }

  before { payment_receipt }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:view"

  it "generates the XML for the given payment receipt" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: payment_receipt.id}
      }
    )

    result_data = result["data"]["downloadXmlPaymentReceipt"]

    expect(result_data["id"]).to be_present
    expect(result_data["xmlUrl"]).to be_present
  end
end
