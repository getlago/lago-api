# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceCustomSectionResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:query) do
    <<~GQL
      query($invoiceCustomSectionId: ID!) {
        invoiceCustomSection(id: $invoiceCustomSectionId) {
          id code name description details displayName
        }
      }
    GQL
  end
  let(:organization) { membership.organization }
  let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }

  let_it_be(:membership) { create_default(:membership) }

  before { invoice_custom_section }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[invoice_custom_sections:view invoice_custom_sections:update]

  it "returns a single invoice_custom_section" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "invoice_custom_sections:view",
      query:,
      variables: {invoiceCustomSectionId: invoice_custom_section.id}
    )

    expect(result["data"]["invoiceCustomSection"]).to include(
      "id" => invoice_custom_section.id,
      "code" => invoice_custom_section.code,
      "name" => invoice_custom_section.name,
      "description" => invoice_custom_section.description,
      "details" => invoice_custom_section.details,
      "displayName" => invoice_custom_section.display_name
    )
  end

  it "returns the invoice_custom_section with the update permission only" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "invoice_custom_sections:update",
      query:,
      variables: {invoiceCustomSectionId: invoice_custom_section.id}
    )

    expect(result["data"]["invoiceCustomSection"]["id"]).to eq(invoice_custom_section.id)
  end

  it "returns a forbidden error without the view or update permission" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "invoices:view",
      query:,
      variables: {invoiceCustomSectionId: invoice_custom_section.id}
    )

    expect(result["errors"].first["extensions"]["code"]).to eq("forbidden")
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {invoiceCustomSectionId: invoice_custom_section.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when invoice_custom_section is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "invoice_custom_sections:view",
        query:,
        variables: {invoiceCustomSectionId: "unknown"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
