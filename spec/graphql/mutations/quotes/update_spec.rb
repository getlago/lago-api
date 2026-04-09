# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Update do
  let(:required_permission) { "quotes:update" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:quote) { create(:quote, organization: membership.organization, customer:) }

  let(:input) do
    {
      id: quote.id,
      autoExecute: true,
      backdatedBilling: "start_without_invoices",
      billingItems: {},
      commercialTerms: {},
      contacts: {},
      content: "Test content",
      currency: "USD",
      description: "Test description",
      executionMode: "order_only",
      internalNotes: "Test internal notes",
      legalText: "Test legal text",
      metadata: {},
      orderType: "one_off",
      owners: [membership.user.id]
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateQuoteInput!) {
        updateQuote(input: $input) {
          id,
          customer { id },
          organization { id },
          number,
          version,
          status,
          autoExecute,
          backdatedBilling,
          billingItems,
          commercialTerms,
          contacts,
          content,
          currency,
          description,
          executionMode,
          internalNotes,
          legalText,
          metadata,
          orderType
        }
      }
    GQL
  end

  before do
    membership.organization.enable_feature_flag!(:order_forms)
    quote
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:update"

  context "with valid input", :premium do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )
    end

    it "updates a quote" do
      expect(result["data"]["updateQuote"]).to include(
        "id" => quote.id,
        "customer" => {"id" => customer.id},
        "organization" => {"id" => membership.organization.id},
        "number" => quote.number,
        "version" => quote.version,
        "status" => quote.status,
        "autoExecute" => true,
        "backdatedBilling" => "start_without_invoices",
        "billingItems" => {},
        "commercialTerms" => {},
        "contacts" => {},
        "content" => "Test content",
        "currency" => "USD",
        "description" => "Test description",
        "executionMode" => "order_only",
        "internalNotes" => "Test internal notes",
        "legalText" => "Test legal text",
        "metadata" => {},
        "orderType" => "one_off"
      )
    end
  end
end
