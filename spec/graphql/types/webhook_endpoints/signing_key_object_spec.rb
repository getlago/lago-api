# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::WebhookEndpoints::SigningKeyObject do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:secret_key).of_type("String!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
  end
end
