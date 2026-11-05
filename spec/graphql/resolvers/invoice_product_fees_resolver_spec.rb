# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceProductFeesResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }

  let(:required_permission) { "invoices:view" }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, organization:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:)) }
  let(:fee) do
    create(:fee, invoice:, organization:, subscription: nil, fee_type: "product",
      invoiceable: product, contract:, contract_rate_card:, amount_cents: 1_000,
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card))
  end
  let(:variables) { {invoiceId: invoice.id} }
  let(:query) do
    <<~GQL
      query($invoiceId: ID!, $productIds: [ID!]) {
        invoiceProductFees(invoiceId: $invoiceId, productIds: $productIds, limit: 10) {
          collection { id amountCents contract { id } product { id } productFilter { id } }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  before { fee }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:view"

  it "returns the product fees of the invoice" do
    response = execution["data"]["invoiceProductFees"]

    expect(response["collection"]).to eq([
      {
        "id" => fee.id,
        "amountCents" => "1000",
        "contract" => {"id" => contract.id},
        "product" => {"id" => product.id},
        "productFilter" => nil
      }
    ])
    expect(response["metadata"]).to eq({"currentPage" => 1, "totalCount" => 1})
  end

  context "with a filter" do
    let(:variables) { {invoiceId: invoice.id, productIds: [create(:product, organization:).id]} }

    it "applies it" do
      expect(execution["data"]["invoiceProductFees"]["collection"]).to eq([])
    end
  end

  context "when the invoice is not found" do
    let(:variables) { {invoiceId: create(:invoice, organization: create(:organization)).id} }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
