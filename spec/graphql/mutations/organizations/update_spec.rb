# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Organizations::Update do
  let(:membership) { create(:membership) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateOrganizationInput!) {
        updateOrganization(input: $input) {
          legalNumber
          legalName
          taxIdentificationNumber
          email
          addressLine1
          addressLine2
          state
          zipcode
          city
          country
          defaultCurrency
          netPaymentTerm
          timezone
          emailSettings
          webhookUrl
          euTaxManagement,
          documentNumbering
          documentNumberPrefix
          finalizeZeroAmountInvoice
          billingConfiguration {
            invoiceFooter,
            invoiceGracePeriod,
            documentLocale,
          }
          authenticationMethods
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[organization:update authentication_methods:update]

  it "updates an organization" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: Permission.permissions_hash(:admin),
      query: mutation,
      variables: {
        input: {
          legalNumber: "1234",
          legalName: "Foobar",
          taxIdentificationNumber: "2246",
          email: "foo@bar.com",
          addressLine1: "Line 1",
          addressLine2: "Line 2",
          netPaymentTerm: 10,
          state: "Foobar",
          zipcode: "FOO1234",
          city: "Foobar",
          country: "FR",
          defaultCurrency: "EUR",
          euTaxManagement: true,
          webhookUrl: "https://app.test.dev",
          documentNumberPrefix: "ORG-2",
          finalizeZeroAmountInvoice: false,
          billingConfiguration: {
            invoiceFooter: "invoice footer",
            documentLocale: "fr"
          }
        }
      }
    )

    result_data = result["data"]["updateOrganization"]

    expect(result_data["legalNumber"]).to eq("1234")
    expect(result_data["legalName"]).to eq("Foobar")
    expect(result_data["taxIdentificationNumber"]).to eq("2246")
    expect(result_data["email"]).to eq("foo@bar.com")
    expect(result_data["addressLine1"]).to eq("Line 1")
    expect(result_data["addressLine2"]).to eq("Line 2")
    expect(result_data["state"]).to eq("Foobar")
    expect(result_data["zipcode"]).to eq("FOO1234")
    expect(result_data["city"]).to eq("Foobar")
    expect(result_data["country"]).to eq("FR")
    expect(result_data["defaultCurrency"]).to eq("EUR")
    expect(result_data["netPaymentTerm"]).to eq(10)
    expect(result_data["webhookUrl"]).to eq("https://app.test.dev")
    expect(result_data["documentNumbering"]).to eq("per_customer")
    expect(result_data["documentNumberPrefix"]).to eq("ORG-2")
    expect(result_data["billingConfiguration"]["invoiceFooter"]).to eq("invoice footer")
    expect(result_data["billingConfiguration"]["invoiceGracePeriod"]).to eq(0)
    expect(result_data["billingConfiguration"]["documentLocale"]).to eq("fr")
    expect(result_data["euTaxManagement"]).to be_truthy
    expect(result_data["timezone"]).to eq("TZ_UTC")
    expect(result_data["finalizeZeroAmountInvoice"]).to be false
  end

  context "without organization:update or authentication_methods:update" do
    it "returns a forbidden error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: %w[organization:view organization:invoices:view organization:emails:view developers:manage],
        query: mutation,
        variables: {
          input: {email: "foo@bar2.com"}
        }
      )

      expect_forbidden_error(result)
      expect(membership.organization.reload.email).not_to eq("foo@bar2.com")
    end
  end

  context "with organization:update only", :premium do
    it "updates organization fields and ignores the other protected fields" do
      organization = membership.organization
      original_authentication_methods = organization.authentication_methods
      original_email_settings = organization.email_settings

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: %w[organization:update],
        query: mutation,
        variables: {
          input: {
            email: "foo@bar2.com",
            taxIdentificationNumber: "tax007",
            authenticationMethods: ["email_password"],
            billingConfiguration: {invoiceFooter: "invoice footer"},
            emailSettings: ["invoice_finalized"],
            webhookUrl: "https://app.test.dev"
          }
        }
      )

      result_data = result["data"]["updateOrganization"]

      expect(result_data["email"]).to eq("foo@bar2.com")
      expect(result_data["taxIdentificationNumber"]).to eq("tax007")

      organization.reload
      expect(organization.authentication_methods).to eq(original_authentication_methods)
      expect(organization.invoice_footer).to be_nil
      expect(organization.email_settings).to eq(original_email_settings)
      expect(organization.webhook_endpoints.pluck(:webhook_url)).not_to include("https://app.test.dev")
    end
  end

  context "with authentication_methods:update only" do
    it "updates authentication methods and ignores organization fields" do
      organization = membership.organization

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: %w[authentication_methods:update],
        query: mutation,
        variables: {
          input: {
            email: "foo@bar2.com",
            authenticationMethods: ["email_password"]
          }
        }
      )

      result_data = result["data"]["updateOrganization"]

      expect(result_data["authenticationMethods"]).to eq(["email_password"])
      expect(organization.reload.email).not_to eq("foo@bar2.com")
    end
  end

  context "with view permissions on invoices and emails", :premium do
    it "does not update billing configuration nor email settings" do
      organization = membership.organization
      original_email_settings = organization.email_settings

      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: %w[organization:update organization:invoices:view organization:emails:view],
        query: mutation,
        variables: {
          input: {
            billingConfiguration: {invoiceFooter: "invoice footer"},
            emailSettings: ["invoice_finalized"]
          }
        }
      )

      organization.reload
      expect(organization.invoice_footer).to be_nil
      expect(organization.email_settings).to eq(original_email_settings)
    end
  end

  context "with premium features", :premium do
    let(:timezone) { "TZ_EUROPE_PARIS" }

    it "updates an organization" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: %w[
          organization:update
          organization:emails:view organization:emails:update
          organization:invoices:view organization:invoices:update
          authentication_methods:update
        ],
        query: mutation,
        variables: {
          input: {
            email: "foo@bar.com",
            timezone:,
            billingConfiguration: {
              invoiceGracePeriod: 3
            },
            emailSettings: ["invoice_finalized"],
            authenticationMethods: ["google_oauth"]
          }
        }
      )

      result_data = result["data"]["updateOrganization"]

      expect(result_data["timezone"]).to eq(timezone)
      expect(result_data["billingConfiguration"]["invoiceGracePeriod"]).to eq(3)
      expect(result_data["emailSettings"]).to eq(["invoice_finalized"])
      expect(result_data["authenticationMethods"]).to eq(["google_oauth"])
    end

    context "with Etc/GMT+12 timezone" do
      let(:timezone) { "TZ_ETC_GMT_12" }

      it "updates an organization" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: %w[organization:update organization:invoices:view organization:invoices:update],
          query: mutation,
          variables: {
            input: {
              email: "foo@bar.com",
              timezone:,
              billingConfiguration: {
                invoiceGracePeriod: 3
              }
            }
          }
        )

        result_data = result["data"]["updateOrganization"]

        expect(result_data["timezone"]).to eq(timezone)
        expect(result_data["billingConfiguration"]["invoiceGracePeriod"]).to eq(3)
      end
    end
  end
end
