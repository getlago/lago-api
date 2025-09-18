# frozen_string_literal: true

RSpec.describe PaymentProviderCustomers::BaseCustomer do
  subject(:integration_customer) { described_class.new(attributes) }

  let(:attributes) { {} }

  it { is_expected.to belong_to(:organization) }
end
