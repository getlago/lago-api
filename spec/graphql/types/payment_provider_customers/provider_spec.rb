# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviderCustomers::Provider do
  subject { described_class }

  it do
    expect(subject).to have_field(:code).of_type("String")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:is_default).of_type("Boolean!")
    expect(subject).to have_field(:provider_customer_id).of_type("ID")
    expect(subject).to have_field(:provider_payment_methods).of_type("[ProviderPaymentMethodsEnum!]")
    expect(subject).to have_field(:sync_with_provider).of_type("Boolean")
  end
end
