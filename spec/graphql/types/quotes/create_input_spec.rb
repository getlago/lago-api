# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:customer_id).of_type("ID!")
    expect(subject).to accept_argument(:order_type).of_type("QuoteOrderTypeEnum!")
    expect(subject).to accept_argument(:owners).of_type("[ID!]")
    expect(subject).to accept_argument(:subscription_id).of_type("ID")
  end
end
