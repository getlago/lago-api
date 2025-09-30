# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethod do
  subject { build(:payment_method) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:customer) }
  it { is_expected.to belong_to(:payment_provider_customer).class_name("PaymentProviderCustomers::BaseCustomer") }
end
