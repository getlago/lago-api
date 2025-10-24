# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::Object do
  subject { described_class }

  it "has the expected fields with correct types" do
    expect(subject).to have_field(:customer).of_type("Customer!")
    expect(subject).to have_field(:billing_entity).of_type("BillingEntity!")

    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:number).of_type("String!")
    expect(subject).to have_field(:sequential_id).of_type("ID!")

    expect(subject).to have_field(:self_billed).of_type("Boolean!")
    expect(subject).to have_field(:version_number).of_type("Int!")

    expect(subject).to have_field(:invoice_type).of_type("InvoiceTypeEnum!")
    expect(subject).to have_field(:payment_dispute_losable).of_type("Boolean!")
    expect(subject).to have_field(:payment_dispute_lost_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:payment_status).of_type("InvoicePaymentStatusTypeEnum!")
    expect(subject).to have_field(:status).of_type("InvoiceStatusTypeEnum!")
    expect(subject).to have_field(:voidable).of_type("Boolean!")

    expect(subject).to have_field(:currency).of_type("CurrencyEnum")
    expect(subject).to have_field(:taxes_rate).of_type("Float!")

    expect(subject).to have_field(:charge_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:coupons_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:credit_notes_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:fees_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:prepaid_credit_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:progressive_billing_credit_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:sub_total_excluding_taxes_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:sub_total_including_taxes_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:taxes_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:total_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:total_due_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:total_paid_amount_cents).of_type("BigInt!")

    expect(subject).to have_field(:issuing_date).of_type("ISO8601Date!")
    expect(subject).to have_field(:payment_due_date).of_type("ISO8601Date!")
    expect(subject).to have_field(:payment_overdue).of_type("Boolean!")
    expect(subject).to have_field(:all_charges_have_fees).of_type("Boolean!")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")

    expect(subject).to have_field(:creditable_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:refundable_amount_cents).of_type("BigInt!")

    expect(subject).to have_field(:file_url).of_type("String")
    expect(subject).to have_field(:xml_url).of_type("String")
    expect(subject).to have_field(:metadata).of_type("[InvoiceMetadata!]")

    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")
    expect(subject).to have_field(:applied_taxes).of_type("[InvoiceAppliedTax!]")
    expect(subject).to have_field(:credit_notes).of_type("[CreditNote!]")
    expect(subject).to have_field(:fees).of_type("[Fee!]")
    expect(subject).to have_field(:invoice_subscriptions).of_type("[InvoiceSubscription!]")
    expect(subject).to have_field(:subscriptions).of_type("[Subscription!]")

    expect(subject).to have_field(:external_hubspot_integration_id).of_type("String")
    expect(subject).to have_field(:external_salesforce_integration_id).of_type("String")
    expect(subject).to have_field(:external_integration_id).of_type("String")
    expect(subject).to have_field(:integration_hubspot_syncable).of_type("Boolean!")
    expect(subject).to have_field(:integration_salesforce_syncable).of_type("Boolean!")
    expect(subject).to have_field(:integration_syncable).of_type("Boolean!")
    expect(subject).to have_field(:payments).of_type("[Payment!]")

    expect(subject).to have_field(:tax_provider_id).of_type("String")

    expect(subject).to have_field(:regenerated_invoice_id).of_type("String")
    expect(subject).to have_field(:voided_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:voided_invoice_id).of_type("String")
  end
end
