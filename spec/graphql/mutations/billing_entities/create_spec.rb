# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::BillingEntities::Create do
  let(:required_permission) { "billing_entities:create" }
  let(:membership) { create(:membership, organization:) }
  let(:organization) { create(:organization) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateBillingEntityInput!) {
        createBillingEntity(input: $input) {
          id
          name,
          code,
          defaultCurrency,
          email,
          legalName,
          legalNumber,
          logoUrl,
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

  let(:input) do
    {
      code: "NEW-0001",
      name: "New entity",
      email: "new@email.com",
      legalName: "New legal name",
      legalNumber: "1234567890",
      taxIdentificationNumber: "Tax-1234",
      addressLine1: "Calle de la Princesa 1",
      addressLine2: "Apt 1",
      city: "Barcelona",
      state: "Barcelona",
      zipcode: "08001",
      country: "ES",
      defaultCurrency: "EUR",
      timezone: "TZ_EUROPE_MADRID",
      documentNumbering: "per_billing_entity",
      documentNumberPrefix: "NEW-0001",
      euTaxManagement: true,
      finalizeZeroAmountInvoice: true,
      netPaymentTerm: 15,
      logo: logo,
      emailSettings: ["invoice_finalized", "credit_note_created"],
      billingConfiguration: {
        invoiceFooter: "invoice footer",
        documentLocale: "es",
        invoiceGracePeriod: 10
      }
    }
  end

  let(:logo) do
    logo_file = File.read(Rails.root.join("spec/factories/images/logo.png"))
    base64_logo = Base64.encode64(logo_file)

    "data:image/png;base64,#{base64_logo}"
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "billing_entities:create"

  it "returns a feaature not available error" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )

    expect_graphql_error(
      result:,
      message: "forbidden"
    )
  end

  context "when the organization can create billing entities" do
    let(:organization) { create(:organization, premium_integrations: %w[multi_entities_enterprise]) }

    it "creates a billing entity for the current organization" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      result_data = result["data"]["createBillingEntity"]
      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq("NEW-0001")
      expect(result_data["name"]).to eq("New entity")
      expect(result_data["email"]).to eq("new@email.com")
      expect(result_data["legalName"]).to eq("New legal name")
      expect(result_data["legalNumber"]).to eq("1234567890")
      expect(result_data["taxIdentificationNumber"]).to eq("Tax-1234")
      expect(result_data["addressLine1"]).to eq("Calle de la Princesa 1")
      expect(result_data["addressLine2"]).to eq("Apt 1")
      expect(result_data["state"]).to eq("Barcelona")
      expect(result_data["city"]).to eq("Barcelona")
      expect(result_data["zipcode"]).to eq("08001")
      expect(result_data["country"]).to eq("ES")
      expect(result_data["defaultCurrency"]).to eq("EUR")
      expect(result_data["timezone"]).to eq("TZ_EUROPE_MADRID")
      expect(result_data["documentNumbering"]).to eq("per_billing_entity")
      expect(result_data["documentNumberPrefix"]).to eq("NEW-0001")
      expect(result_data["euTaxManagement"]).to eq true
      expect(result_data["finalizeZeroAmountInvoice"]).to eq true
      expect(result_data["netPaymentTerm"]).to eq(15)
      expect(result_data["logoUrl"]).to match(%r{.*/rails/active_storage/blobs/redirect/.*/logo})
      expect(result_data["emailSettings"]).to be_nil
      expect(result_data["billingConfiguration"]).to be_nil
    end

    context "with extra view permissions" do
      let(:permissions) do
        [required_permission].concat(%w[billing_entities:emails:view billing_entities:invoices:view])
      end

      it "includes the email settings and billing configuration in the response" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions:,
          query: mutation,
          variables: {input:}
        )

        result_data = result["data"]["createBillingEntity"]
        expect(result_data["emailSettings"]).to eq(["invoice_finalized", "credit_note_created"])
        expect(result_data["billingConfiguration"]["invoiceFooter"]).to eq("invoice footer")
        expect(result_data["billingConfiguration"]["documentLocale"]).to eq("es")
        expect(result_data["billingConfiguration"]["invoiceGracePeriod"]).to eq(10)
      end
    end
  end
end
