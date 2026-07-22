# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceConnection do
  subject(:invoice_connection) { build(:invoice_connection) }

  describe "enums" do
    it do
      expect(invoice_connection).to define_enum_for(:category)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(payment: "payment", tax: "tax", accounting: "accounting", crm: "crm")
    end
  end

  describe "associations" do
    it do
      expect(invoice_connection).to belong_to(:organization)
      expect(invoice_connection).to belong_to(:invoice)
      expect(invoice_connection).to belong_to(:payment_provider_customer)
        .optional
        .class_name("PaymentProviderCustomers::BaseCustomer")
      expect(invoice_connection).to belong_to(:integration_customer)
        .optional
        .class_name("IntegrationCustomers::BaseCustomer")
    end
  end
end
