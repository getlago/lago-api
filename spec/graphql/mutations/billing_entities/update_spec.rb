# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::BillingEntities::Update, type: :graphql do
  let(:required_permission) { "billing_entities:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateBillingEntityInput!) {
        updateBillingEntity(input: $input) {
          id
          name,
          code,
          defaultCurrency,
          email,
          legalName,
          legalNumber,
          taxIdentificationNumber,
          addressLine1,
          addressLine2,
          city,
          country,
          netPaymentTerm,
          state,
          zipcode,
          timezone,
          euTaxManagement,
          documentNumberPrefix,
          documentNumbering,
          emailSettings,
          finalizeZeroAmountInvoice,
          billingConfiguration {
            invoiceFooter,
            invoiceGracePeriod,
            documentLocale,
          }
        }
      }
    GQL
  end

  before do
    allow(BillingEntities::UpdateService).to receive(:call).and_call_original
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "billing_entities:update"

  # We're not allowing now to update a billing entity, but this endpoint is needed for FE
  it "returns default billing entity for the current organization" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          name: "Upddated entity",
          code: "updated_entity"
        }
      }
    )

    result_data = result["data"]["updateBillingEntity"]
    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq(organization.default_billing_entity.name)
    expect(result_data["code"]).to eq(organization.default_billing_entity.code)
    expect(BillingEntities::UpdateService).not_to have_received(:call)
  end
end
