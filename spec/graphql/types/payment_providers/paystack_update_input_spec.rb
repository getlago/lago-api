# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviders::PaystackUpdateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:code).of_type("String")
    expect(subject).to accept_argument(:id).of_type("ID!")
    expect(subject).to accept_argument(:name).of_type("String")
    expect(subject).to accept_argument(:success_redirect_url).of_type("String")
    expect(subject).not_to accept_argument(:flow_id)
    expect(subject).not_to accept_argument(:supports_3ds)
  end
end
