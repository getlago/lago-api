# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::InvoiceCustomSectionsResolver, type: :graphql do
  let(:required_permission) { "invoice_custom_sections:view" }
  let(:query) do
    <<~GQL
      query() {
        invoiceCustomSections(limit: 5) {
          collection { id, name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_custom_sections) do
    [
      create(:invoice_custom_section, organization:, name: "x"),
      create(:invoice_custom_section, organization:, name: "r"),
      create(:invoice_custom_section, organization:, name: "c"),
      create(:invoice_custom_section, organization:, name: "a"),
      create(:invoice_custom_section, organization:, name: "z"),
      create(:invoice_custom_section, organization:, name: "n")
    ]
  end

  before do
    organization.selected_invoice_custom_sections.concat(invoice_custom_sections[2..4])
    customer.selected_invoice_custom_sections.concat(invoice_custom_sections[0..1])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoice_custom_sections:view"

  it "returns a list of sorted invoice_custom_sections: alphabetical, selected first without duplicates" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    invoice_custom_sections_response = result["data"]["invoiceCustomSections"]

    aggregate_failures do
      expect(invoice_custom_sections_response["collection"].count).to eq(5)
      expect(invoice_custom_sections_response["collection"].map { |ics| ics["name"] }.join("")).to eq("acznr")

      expect(invoice_custom_sections_response["metadata"]["currentPage"]).to eq(1)
      expect(invoice_custom_sections_response["metadata"]["totalCount"]).to eq(6)
    end
  end
end
