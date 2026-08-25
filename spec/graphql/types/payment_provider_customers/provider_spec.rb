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

      it "derives the provider from the row type" do
        type = described_class.authorized_new(connection, context)

        expect(type.payment_provider).to eq("stripe")
      end
    end

    context "with a provider-less row" do
      let(:connection) do
        PaymentProviderCustomers::BaseCustomer.new(
          type: "PaymentProviderCustomers::BaseCustomer",
          code: PaymentProviderCustomers::BaseCustomer::MANUAL_CODE
        )
      end

      it "resolves the provider to nil" do
        type = described_class.authorized_new(connection, context)

        expect(type.payment_provider).to be_nil
      end
    end
  end

  describe "payment provider code over several rows" do
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }

    let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_eu") }
    let(:adyen_provider) { create(:adyen_provider, organization:, code: "adyen_us") }

    let(:customer_one) do
      create(:customer, organization:, payment_provider: "stripe", payment_provider_code: "stripe_eu")
    end
    let(:customer_two) do
      create(:customer, organization:, payment_provider: "adyen", payment_provider_code: "adyen_us")
    end

    let(:query) do
      <<~GQL
        query($idOne: ID!, $idTwo: ID!) {
          one: customer(id: $idOne) {
            providerCustomer { paymentProvider paymentProviderCode }
          }
          two: customer(id: $idTwo) {
            providerCustomer { paymentProvider paymentProviderCode }
          }
        }
      GQL
    end

    before do
      create(:stripe_customer, customer: customer_one, payment_provider: stripe_provider)
      create(:adyen_customer, customer: customer_two, payment_provider: adyen_provider)
    end

    it "resolves each row's own provider within a single execution" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "customers:view",
        query:,
        variables: {idOne: customer_one.id, idTwo: customer_two.id}
      )

      expect(result["data"]["one"]["providerCustomer"]).to eq(
        "paymentProvider" => "stripe", "paymentProviderCode" => "stripe_eu"
      )
      expect(result["data"]["two"]["providerCustomer"]).to eq(
        "paymentProvider" => "adyen", "paymentProviderCode" => "adyen_us"
      )
    end
  end
end
