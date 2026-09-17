# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:billing_entity_id).of_type("ID")
    expect(subject).to accept_argument(:billing_items).of_type("JSON")
    expect(subject).to accept_argument(:content).of_type("String")
    expect(subject).to accept_argument(:customer_id).of_type("ID!")
    expect(subject).to accept_argument(:order_type).of_type("OrderTypeEnum!")
    expect(subject).to accept_argument(:owners).of_type("[ID!]")
    expect(subject).to accept_argument(:subscription_id).of_type("ID")
  end

  it "does not accept a currency: the deal currency is derived at creation" do
    expect(subject).not_to accept_argument(:currency)
  end
end
