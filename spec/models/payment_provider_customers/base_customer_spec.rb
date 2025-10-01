# frozen_string_literal: true

RSpec.describe PaymentProviderCustomers::BaseCustomer do
  subject(:integration_customer) { described_class.new(attributes) }

  let(:attributes) { {} }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:payment_methods).with_foreign_key(:payment_provider_customer_id) }
end
