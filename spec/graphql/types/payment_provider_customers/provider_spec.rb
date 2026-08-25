# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviderCustomers::Provider do
  subject { described_class }

  it do
    expect(subject).to have_field(:code).of_type("String")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:is_default).of_type("Boolean!")
    expect(subject).to have_field(:payment_methods).of_type("PaymentMethodCollection!")
    expect(subject).to have_field(:payment_provider).of_type("ProviderTypeEnum")
    expect(subject).to have_field(:payment_provider_code).of_type("String")
    expect(subject).to have_field(:provider_customer_id).of_type("ID")
    expect(subject).to have_field(:provider_payment_methods).of_type("[ProviderPaymentMethodsEnum!]")
    expect(subject).to have_field(:sync_with_provider).of_type("Boolean")
  end

  describe "provider identity fields" do
    let(:context) { GraphQL::Query.new(LagoApiSchema, "{ __typename }").context }

    context "with a provider-backed connection" do
      let(:payment_provider) { create(:stripe_provider, code: "stripe_eu") }
      let(:connection) { create(:stripe_customer, payment_provider:) }

      it "derives the provider from the row and the code from its association" do
        type = described_class.authorized_new(connection, context)

        expect(type.payment_provider).to eq("stripe")
        expect(type.payment_provider_code).to eq("stripe_eu")
      end
    end

    context "with a provider-less row" do
      let(:connection) do
        PaymentProviderCustomers::BaseCustomer.new(
          type: "PaymentProviderCustomers::BaseCustomer",
          code: PaymentProviderCustomers::BaseCustomer::MANUAL_CODE
        )
      end

      it "resolves both fields to nil" do
        type = described_class.authorized_new(connection, context)

        expect(type.payment_provider).to be_nil
        expect(type.payment_provider_code).to be_nil
      end
    end
  end
end
