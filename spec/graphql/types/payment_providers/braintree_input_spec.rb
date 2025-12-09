# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviders::BraintreeInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:public_key).of_type("String!")
    expect(subject).to accept_argument(:private_key).of_type("String!")
    expect(subject).to accept_argument(:merchant_id).of_type("String!")
    expect(subject).to accept_argument(:name).of_type("String!")
    expect(subject).to accept_argument(:success_redirect_url).of_type("String")
  end
end
