# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Customers::Update do
  let(:required_permissions) { "customers:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, legal_name: nil) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:tax) { create(:tax, organization:) }
  let(:external_id) { SecureRandom.uuid }
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 2, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInput!) {
        updateCustomer(input: $input) {
          id
          name
          firstname
          lastname
          displayName
          customerType
          taxIdentificationNumber
          externalId
          paymentProvider
          currency
          timezone
          netPaymentTerm
          canEditAttributes
          invoiceGracePeriod
          finalizeZeroAmountInvoice
          billingEntity { code }
          providerCustomer { id, providerCustomerId, providerPaymentMethods }
          billingConfiguration { id, documentLocale }
          metadata { id, key, value, displayInInvoice }
          taxes { code }
          configurableInvoiceCustomSections { id }
        }
      }
    GQL
  end

  let(:body) do
    {
      object: "event",
      data: {}
    }
  end

  let(:input) do
    {
      id: customer.id,
      name: "Updated customer",
      firstname: "Updated firstname",
      lastname: "Updated lastname",
      customerType: "individual",
      taxIdentificationNumber: "2246",
      externalId: external_id,
      paymentProvider: "stripe",
      currency: "USD",
      netPaymentTerm: 3,
      finalizeZeroAmountInvoice: "skip",
      billingEntityCode: billing_entity.code,
      providerCustomer: {
        providerCustomerId: "cu_12345",
        providerPaymentMethods: %w[card sepa_debit]
      },
      billingConfiguration: {
        documentLocale: "fr"
      },
      metadata: [
        {
          key: "test-key",
          value: "value",
          displayInInvoice: true
        }
      ],
      taxCodes: [tax.code],
      configurableInvoiceCustomSectionIds: invoice_custom_sections.map(&:id)
    }
  end

  before do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: body.to_json, headers: {})

    allow(Stripe::Customer).to receive(:update).and_return(BaseService::Result.new)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", %w[
    customers:update
    customer_settings:update:tax_rates
    customer_settings:update:payment_terms
    customer_settings:update:grace_period
    customer_settings:update:lang
  ]

  it "updates a customer" do
    stripe_provider

    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permissions,
      query: mutation,
      variables: {
        input:
      }
    )

    result_data = result["data"]["updateCustomer"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["name"]).to eq("Updated customer")
      expect(result_data["firstname"]).to eq("Updated firstname")
      expect(result_data["lastname"]).to eq("Updated lastname")
      expect(result_data["displayName"]).to eq("Updated customer - Updated firstname Updated lastname")
      expect(result_data["customerType"]).to eq("individual")
      expect(result_data["taxIdentificationNumber"]).to eq("2246")
      expect(result_data["externalId"]).to eq(external_id)
      expect(result_data["paymentProvider"]).to eq("stripe")
      expect(result_data["currency"]).to eq("USD")
      expect(result_data["timezone"]).to be_nil
      expect(result_data["netPaymentTerm"]).to eq(3)
      expect(result_data["invoiceGracePeriod"]).to be_nil
      expect(result_data["finalizeZeroAmountInvoice"]).to eq("skip")
      expect(result_data["providerCustomer"]["id"]).to be_present
      expect(result_data["providerCustomer"]["providerCustomerId"]).to eq("cu_12345")
      expect(result_data["providerCustomer"]["providerPaymentMethods"]).to eq(%w[card sepa_debit])
      expect(result_data["billingConfiguration"]["documentLocale"]).to eq("fr")
      expect(result_data["billingConfiguration"]["id"]).to eq("#{customer.id}-c0nf")
      expect(result_data["metadata"][0]["key"]).to eq("test-key")
      expect(result_data["taxes"][0]["code"]).to eq(tax.code)
      expect(result_data["configurableInvoiceCustomSections"]).to match_array(invoice_custom_sections.map { |section| {"id" => section.id} })
      expect(result_data["billingEntity"]["code"]).to eq(billing_entity.code)
    end
  end

  context "with premium feature" do
    around { |test| lago_premium!(&test) }

    it "updates a customer" do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permissions,
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            externalId: SecureRandom.uuid,
            name: "Updated customer",
            timezone: "TZ_EUROPE_PARIS",
            invoiceGracePeriod: 2
          }
        }
      )

      result_data = result["data"]["updateCustomer"]

      aggregate_failures do
        expect(result_data["timezone"]).to eq("TZ_EUROPE_PARIS")
        expect(result_data["invoiceGracePeriod"]).to eq(2)
      end
    end
  end

  context "when user can only update customer settings" do
    around { |test| lago_premium!(&test) }

    it "updates a customer" do
      result = execute_graphql(
        current_user: membership.user,
        permissions: %w[
          customer_settings:update:tax_rates
          customer_settings:update:payment_terms
          customer_settings:update:grace_period
          customer_settings:update:lang
        ],
        query: mutation,
        variables: {
          input: input.merge({
            invoiceGracePeriod: 2,
            timezone: "TZ_EUROPE_PARIS"
          })
        }
      )

      result_data = result["data"]["updateCustomer"]

      aggregate_failures do
        # What should have changed
        expect(result_data["id"]).to be_present
        expect(result_data["taxes"][0]["code"]).to eq(tax.code)
        expect(result_data["netPaymentTerm"]).to eq(3)
        expect(result_data["invoiceGracePeriod"]).to eq 2
        expect(result_data["billingConfiguration"]["documentLocale"]).to eq("fr")

        # What should not have changed
        expect(result_data["name"]).not_to eq("Updated customer")
        expect(result_data["taxIdentificationNumber"]).to be_nil
        expect(result_data["externalId"]).not_to eq(external_id)
        expect(result_data["paymentProvider"]).to be_nil
        expect(result_data["currency"]).to eq("EUR")
        expect(result_data["timezone"]).to be_nil
        expect(result_data["providerCustomer"]).to be_nil
        expect(result_data["metadata"]).to be_empty
      end
    end
  end
end
