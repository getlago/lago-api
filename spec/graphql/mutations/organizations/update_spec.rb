# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Organizations::Update do
  include_context "with mocked security logger"

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership, refind: true) { create_default(:membership) }
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
          customerPortalLockedFields
          webhookUrl
          euTaxManagement,
          documentNumbering
          documentNumberPrefix
          finalizeZeroAmountInvoice
          documentUrlExpirationDays
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
  it_behaves_like "requires permission", "organization:update"

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
          customerPortalLockedFields: %w[name country],
          documentUrlExpirationDays: 90,
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
    expect(result_data["customerPortalLockedFields"]).to eq(%w[name country])
    expect(result_data["documentUrlExpirationDays"]).to eq(90)
  end

  context "without organization:update" do
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
      original_endpoints = organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)

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
      expect(organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)).to eq(original_endpoints)
      expect(security_logger).not_to have_received(:produce).with(hash_including(log_type: "webhook_endpoint"))
    end
  end

  context "with developers:manage" do
    subject(:result) do
      execute_graphql(
        current_user: target_membership.user,
        current_organization: target_membership.organization,
        current_membership: target_membership,
        permissions: %w[organization:update developers:manage],
        query: mutation,
        variables: {input: {webhookUrl: webhook_url}}
      )
    end

    let(:target_organization) { create(:organization) }
    let(:target_membership) { create(:membership, organization: target_organization) }
    let(:webhook_url) { "https://hooks.example.com/new" }

    it "updates the endpoint" do
      target_endpoint = target_organization.webhook_endpoints.order(:id).first

      expect(result["data"]["updateOrganization"]["webhookUrl"]).to eq(webhook_url)
      expect(target_endpoint.reload.webhook_url).to eq(webhook_url)
      expect(security_logger).to have_received(:produce).with(hash_including(log_event: "webhook_endpoint.updated"))
    end

    context "when the organization has several webhook endpoints" do
      let(:other_endpoint) { create(:webhook_endpoint, organization: target_organization) }
      let(:target_endpoint) { target_organization.webhook_endpoints.order(:id).first }
      let(:untouched_endpoint) { target_organization.webhook_endpoints.order(:id).last }
      let(:untouched_url) { untouched_endpoint.webhook_url }

      before do
        other_endpoint
        untouched_url
      end

      it "updates only the endpoint with the lowest id" do
        expect(result["data"]["updateOrganization"]["webhookUrl"]).to eq(webhook_url)
        expect(target_endpoint.reload.webhook_url).to eq(webhook_url)
        expect(untouched_endpoint.reload.webhook_url).to eq(untouched_url)
      end
    end

    context "when the organization has no webhook endpoint" do
      let(:target_organization) { create(:organization, webhook_url: nil) }

      it "creates the endpoint" do
        expect(result["data"]["updateOrganization"]["webhookUrl"]).to eq(webhook_url)
        expect(target_organization.webhook_endpoints.pluck(:webhook_url)).to eq([webhook_url])
        expect(security_logger).to have_received(:produce).with(hash_including(log_event: "webhook_endpoint.created"))
      end
    end

    context "when the url is invalid" do
      let(:webhook_url) { "foobar" }

      it "returns the validation error and leaves the endpoint unchanged" do
        endpoints_before = target_organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)

        expect_unprocessable_entity(result, details: {webhookUrl: ["url_is_invalid"]})
        expect(target_organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)).to eq(endpoints_before)
        expect(security_logger).not_to have_received(:produce).with(hash_including(log_type: "webhook_endpoint"))
      end
    end
  end

  context "with authentication_methods:update but without organization:update" do
    it "returns a forbidden error" do
      organization = membership.organization
      original_authentication_methods = organization.authentication_methods

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: %w[authentication_methods:update],
        query: mutation,
        variables: {
          input: {authenticationMethods: ["email_password"]}
        }
      )

      expect_forbidden_error(result)
      expect(organization.reload.authentication_methods).to eq(original_authentication_methods)
    end
  end

  context "with organization:update and authentication_methods:update" do
    it "updates authentication methods" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: %w[organization:update authentication_methods:update],
        query: mutation,
        variables: {
          input: {authenticationMethods: ["email_password"]}
        }
      )

      expect(result["data"]["updateOrganization"]["authenticationMethods"]).to eq(["email_password"])
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
