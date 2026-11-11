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

  context "with the fields of the invoice page" do
    let(:query) do
      <<~GQL
        query($invoiceId: ID!) {
          invoiceProductFees(invoiceId: $invoiceId, limit: 100) {
            collection { id itemCode itemName appliedTaxes { taxRate } trueUpParentFee { id productFilter { id } } product { id } }
          }
        }
      GQL
    end
    let(:small_invoice) { create(:invoice, organization:, customer:) }
    let(:large_invoice) { create(:invoice, organization:, customer:) }

    before do
      taxed_fee(small_invoice, true_up_parent_fee: taxed_fee(small_invoice))
      2.times { taxed_fee(large_invoice, true_up_parent_fee: taxed_fee(large_invoice)) }
    end

    def taxed_fee(fee_invoice, true_up_parent_fee: nil)
      create(:fee, invoice: fee_invoice, organization:, subscription: nil, fee_type: "product",
        invoiceable: product, contract:, contract_rate_card:, amount_cents: 1_000, true_up_parent_fee:,
        rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card))
        .tap { create(:fee_applied_tax, fee: it, organization:) }
    end

    def query_count(fee_invoice)
      capture_sql do
        execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {invoiceId: fee_invoice.id}
        )
      end.size
    end

    it "runs the same queries whatever the number of fees on the page" do
      query_count(small_invoice)

      expect(query_count(large_invoice)).to eq(query_count(small_invoice))
    end
  end

  context "when the invoice is not found" do
    let(:variables) { {invoiceId: create(:invoice, organization: create(:organization)).id} }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
