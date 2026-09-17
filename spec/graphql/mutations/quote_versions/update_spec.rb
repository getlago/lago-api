# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::QuoteVersions::Update do
  let(:required_permission) { "quotes:update" }
  let(:membership) { create(:membership) }
  let(:quote_version) { create(:quote_version, organization: membership.organization) }

  let(:input) do
    {
      id: quote_version.id,
      billingItems: {},
      content: "Test content",
      currency: "EUR"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateQuoteVersionInput!) {
        updateQuoteVersion(input: $input) {
          id,
          organization { id },
          version,
          status,
          billingItems,
          content,
          currency
        }
      }
    GQL
  end

  before do
    membership.organization.enable_feature_flag!(:order_forms)
    quote_version
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

    it "updates a quote version" do
      expect(result["data"]["updateQuoteVersion"]).to include(
        "id" => quote_version.id,
        "organization" => {"id" => membership.organization.id},
        "version" => quote_version.version,
        "status" => quote_version.status,
        "billingItems" => {},
        "content" => "Test content",
        "currency" => "EUR"
      )
    end
  end

  # The response payload is what the pages rendering a quote read, so the shape of billing_items after
  # a currency change is asserted here rather than only at the service.
  context "when the currency change realigns the billing items", :premium do
    let(:organization) { membership.organization }
    let(:quote) { create(:quote, organization:) }
    let(:plan) { create(:plan, organization:, amount_currency: "EUR") }
    let(:overrides) { {"amountCurrency" => "USD"} }
    let(:quote_version) do
      create(
        :quote_version,
        quote:,
        organization:,
        currency: "USD",
        billing_items: {
          "plans" => [
            {
              "id" => plan.id,
              "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
              "type" => "plan",
              "payload" => {"code" => plan.code, "startDate" => Date.current.iso8601},
              "overrides" => overrides
            }
          ]
        }
      )
    end
    let(:input) { {id: quote_version.id, currency: "EUR"} }

    let(:returned_overrides) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      ).dig("data", "updateQuoteVersion", "billingItems", "plans", 0, "overrides")
    end

    it "returns an empty overrides object rather than dropping the key" do
      expect(returned_overrides).to eq({})
      expect(returned_overrides).not_to be_nil
    end

    context "when the item also carries a negotiated price" do
      let(:overrides) { {"amountCurrency" => "USD", "amountCents" => 150_000, "name" => "Enterprise deal"} }

      it "keeps the negotiated values and only drops the currency" do
        expect(returned_overrides).to eq({"amountCents" => 150_000, "name" => "Enterprise deal"})
      end
    end

    context "when the deal moves to a currency the plan is not priced in" do
      let(:overrides) { {"amountCents" => 150_000} }
      let(:input) { {id: quote_version.id, currency: "GBP"} }

      it "restates the currency alongside the negotiated price" do
        expect(returned_overrides).to eq({"amountCents" => 150_000, "amountCurrency" => "GBP"})
      end
    end
  end

  context "when quote version is not found", :premium do
    let(:input) do
      {
        id: "00000000-0000-0000-0000-000000000000",
        billingItems: {},
        content: "Test content",
        currency: "EUR"
      }
    end

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_not_found(result)
    end
  end

  context "when quote version is not in draft state", :premium do
    let(:quote_version) { create(:quote_version, :voided, organization: membership.organization) }

    it "returns a validation error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_graphql_error(result:, message: "Unprocessable Entity", details: {status: ["not_editable"]})
    end
  end
end
