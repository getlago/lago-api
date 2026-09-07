# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingObjectConnection do
  subject(:billing_object_connection) { build(:billing_object_connection) }

  describe "enums" do
    it do
      expect(billing_object_connection).to define_enum_for(:category)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(payment: "payment", tax: "tax", accounting: "accounting", crm: "crm")

      expect(billing_object_connection).to define_enum_for(:behavior)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(specific: "specific", skip: "skip")
    end
  end

  describe "associations" do
    it do
      expect(billing_object_connection).to belong_to(:organization)
      expect(billing_object_connection).to belong_to(:owner)
      expect(billing_object_connection).to belong_to(:payment_provider_customer)
        .class_name("PaymentProviderCustomers::BaseCustomer").optional
      expect(billing_object_connection).to belong_to(:integration_customer)
        .class_name("IntegrationCustomers::BaseCustomer").optional
    end
  end
end
