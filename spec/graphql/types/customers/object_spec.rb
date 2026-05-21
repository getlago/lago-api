# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Customers::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:billing_entity).of_type("BillingEntity!")

    expect(subject).to have_field(:account_type).of_type("CustomerAccountTypeEnum!")
    expect(subject).to have_field(:customer_type).of_type(Types::Customers::CustomerTypeEnum)
    expect(subject).to have_field(:display_name).of_type("String!")
    expect(subject).to have_field(:external_id).of_type("String!")
    expect(subject).to have_field(:firstname).of_type("String")
    expect(subject).to have_field(:lastname).of_type("String")
    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:sequential_id).of_type("String!")
    expect(subject).to have_field(:slug).of_type("String!")

    expect(subject).to have_field(:address_line1).of_type("String")
    expect(subject).to have_field(:address_line2).of_type("String")

    expect(subject).to have_field(:applicable_timezone).of_type("TimezoneEnum!")
    expect(subject).to have_field(:city).of_type("String")
    expect(subject).to have_field(:country).of_type("CountryCode")
    expect(subject).to have_field(:currency).of_type("CurrencyEnum")
    expect(subject).to have_field(:email).of_type("String")
    expect(subject).to have_field(:external_salesforce_id).of_type("String")
    expect(subject).to have_field(:invoice_grace_period).of_type("Int")
    expect(subject).to have_field(:legal_name).of_type("String")
    expect(subject).to have_field(:legal_number).of_type("String")
    expect(subject).to have_field(:logo_url).of_type("String")
    expect(subject).to have_field(:net_payment_term).of_type("Int")
    expect(subject).to have_field(:payment_provider).of_type("ProviderTypeEnum")
    expect(subject).to have_field(:payment_provider_code).of_type("String")
    expect(subject).to have_field(:phone).of_type("String")
    expect(subject).to have_field(:state).of_type("String")
    expect(subject).to have_field(:tax_identification_number).of_type("String")
    expect(subject).to have_field(:timezone).of_type("TimezoneEnum")
    expect(subject).to have_field(:url).of_type("String")
    expect(subject).to have_field(:zipcode).of_type("String")

    expect(subject).to have_field(:metadata).of_type("[CustomerMetadata!]")

    expect(subject).to have_field(:billing_configuration).of_type("CustomerBillingConfiguration")

    expect(subject).to have_field(:shipping_address).of_type("CustomerAddress")

    expect(subject).to have_field(:anrok_customer).of_type("AnrokCustomer")
    expect(subject).to have_field(:avalara_customer).of_type("AvalaraCustomer")
    expect(subject).to have_field(:hubspot_customer).of_type("HubspotCustomer")
    expect(subject).to have_field(:netsuite_customer).of_type("NetsuiteCustomer")
    expect(subject).to have_field(:salesforce_customer).of_type("SalesforceCustomer")
    expect(subject).to have_field(:provider_customer).of_type("ProviderCustomer")
    expect(subject).to have_field(:subscriptions).of_type("[Subscription!]!")
    expect(subject).to have_field(:xero_customer).of_type("XeroCustomer")

    expect(subject).to have_field(:invoices).of_type("[Invoice!]")

    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")
    expect(subject).to have_field(:applied_add_ons).of_type("[AppliedAddOn!]")
    expect(subject).to have_field(:applied_coupons).of_type("[AppliedCoupon!]")
    expect(subject).to have_field(:taxes).of_type("[Tax!]")

    expect(subject).to have_field(:credit_notes).of_type("[CreditNote!]")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:deleted_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")

    expect(subject).to have_field(:active_subscriptions_count).of_type("Int!")
    expect(subject).to have_field(:credit_notes_balance_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:credit_notes_balances).of_type("[CustomerCreditNotesBalance!]!")
    expect(subject).to have_field(:credit_notes_credits_available_count).of_type("Int!")
    expect(subject).to have_field(:has_active_wallet).of_type("Boolean!")
    expect(subject).to have_field(:has_credit_notes).of_type("Boolean!")
    expect(subject).to have_field(:has_overdue_invoices).of_type("Boolean!")
    expect(subject).to have_field(:overdue_balances).of_type("[CustomerOverdueBalance!]!")

    expect(subject).to have_field(:can_edit_attributes).of_type("Boolean!")
    expect(subject).to have_field(:finalize_zero_amount_invoice).of_type("FinalizeZeroAmountInvoiceEnum")

    expect(subject).to have_field(:applied_dunning_campaign).of_type("DunningCampaign")
    expect(subject).to have_field(:exclude_from_dunning_campaign).of_type("Boolean!")
    expect(subject).to have_field(:last_dunning_campaign_attempt).of_type("Int!")
    expect(subject).to have_field(:last_dunning_campaign_attempt_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:configurable_invoice_custom_sections).of_type("[InvoiceCustomSection!]")

    expect(subject).to have_field(:error_details).of_type("[ErrorDetail!]")
  end

  describe "credit notes scalar resolvers with filter arguments" do
    let(:required_permission) { "customers:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:customer) { create(:customer, organization:, currency: "EUR") }
    let(:billing_entity_a) { create(:billing_entity, organization:) }
    let(:billing_entity_b) { create(:billing_entity, organization:) }

    let(:query) do
      <<~GQL
        query($customerId: ID!, $currency: CurrencyEnum, $billingEntityId: ID) {
          customer(id: $customerId) {
            creditNotesBalanceAmountCents(currency: $currency, billingEntityId: $billingEntityId)
            creditNotesCreditsAvailableCount(currency: $currency, billingEntityId: $billingEntityId)
          }
        }
      GQL
    end

    before do
      invoice_eur_a = create(:invoice, customer:, organization:, billing_entity: billing_entity_a)
      invoice_usd_a = create(:invoice, customer:, organization:, billing_entity: billing_entity_a)
      invoice_eur_b = create(:invoice, customer:, organization:, billing_entity: billing_entity_b)

      create(:credit_note, customer:, organization:, invoice: invoice_eur_a,
        total_amount_currency: "EUR", balance_amount_cents: 100, credit_amount_cents: 100)
      create(:credit_note, customer:, organization:, invoice: invoice_usd_a,
        total_amount_currency: "USD", balance_amount_cents: 200, credit_amount_cents: 200)
      create(:credit_note, customer:, organization:, invoice: invoice_eur_b,
        total_amount_currency: "EUR", balance_amount_cents: 400, credit_amount_cents: 400)
    end

    def execute_with(variables)
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: variables.merge(customerId: customer.id)
      )
      result["data"]["customer"]
    end

    context "without filter arguments" do
      it "returns the legacy aggregate across all currencies and billing entities" do
        data = execute_with({})
        expect(data["creditNotesBalanceAmountCents"]).to eq("700")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(3)
      end
    end

    context "with currency filter" do
      it "returns only the EUR subtotal when filtered to EUR" do
        data = execute_with(currency: "EUR")
        expect(data["creditNotesBalanceAmountCents"]).to eq("500")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(2)
      end

      it "returns only the USD subtotal when filtered to USD (cross-currency regression)" do
        data = execute_with(currency: "USD")
        expect(data["creditNotesBalanceAmountCents"]).to eq("200")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(1)
      end
    end

    context "with billing entity filter" do
      it "returns only credit notes linked to invoices of that billing entity" do
        data = execute_with(billingEntityId: billing_entity_a.id)
        expect(data["creditNotesBalanceAmountCents"]).to eq("300")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(2)
      end
    end

    context "with both filters combined" do
      it "returns the intersection" do
        data = execute_with(currency: "EUR", billingEntityId: billing_entity_a.id)
        expect(data["creditNotesBalanceAmountCents"]).to eq("100")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(1)
      end

      it "returns zero when no credit note matches both filters" do
        data = execute_with(currency: "USD", billingEntityId: billing_entity_b.id)
        expect(data["creditNotesBalanceAmountCents"]).to eq("0")
        expect(data["creditNotesCreditsAvailableCount"]).to eq(0)
      end
    end
  end
end
