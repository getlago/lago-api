# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::Create do
  let(:required_permission) { "invoices:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:currency) { "EUR" }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:current_time) { DateTime.new(2023, 7, 19, 12, 12) }
  let(:fees) do
    [
      {
        addOnId: add_on_first.id,
        unitAmountCents: 1200,
        units: 2,
        description: "desc-123",
        invoiceDisplayName: "fee-123",
        taxCodes: [tax.code],
        fromDatetime: current_time.utc.iso8601(3),
        toDatetime: current_time.utc.iso8601(3)
      },
      {
        addOnId: add_on_second.id,
        fromDatetime: current_time.utc.iso8601(3),
        toDatetime: current_time.utc.iso8601(3)
      }
    ]
  end
  let(:mutation) do
    <<-GQL
      mutation($input: CreateInvoiceInput!) {
        createInvoice(input: $input) {
          id,
          feesAmountCents,
          taxesAmountCents,
          totalAmountCents,
          currency,
          taxesRate,
          invoiceType,
          issuingDate,
          appliedTaxes { id taxCode taxRate },
          fees {
            units
            preciseUnitAmount
            properties {
              fromDatetime
              toDatetime
            }
          },
        }
      }
    GQL
  end

  before { tax }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:create"

  it "creates one-off invoice" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          currency:,
          fees:
        }
      }
    )

    result_data = result["data"]["createInvoice"]

    aggregate_failures do
      expect(result_data).to include(
        "id" => String,
        "issuingDate" => Time.current.to_date.to_s,
        "invoiceType" => "one_off",
        "feesAmountCents" => "2800",
        "taxesAmountCents" => "560",
        "totalAmountCents" => "3360",
        "taxesRate" => 20,
        "currency" => "EUR"
      )
      expect(result_data["appliedTaxes"].map { |t| t["taxCode"] }).to contain_exactly(tax.code)
      expect(result_data["fees"]).to contain_exactly(
        {
          "units" => 2.0,
          "preciseUnitAmount" => 12.0,
          "properties" => {
            "fromDatetime" => current_time.to_time.utc.iso8601,
            "toDatetime" => current_time.to_time.utc.iso8601
          }
        },
        {
          "units" => 1.0,
          "preciseUnitAmount" => 4.0,
          "properties" => {
            "fromDatetime" => current_time.to_time.utc.iso8601,
            "toDatetime" => current_time.to_time.utc.iso8601
          }
        }
      )
    end
  end
end
