# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Payloads::LoginUserType do
  subject { described_class }

  it do
    expect(subject).to have_field(:needs_organization).of_type("Boolean!")
    expect(subject).to have_field(:token).of_type("String!")
    expect(subject).to have_field(:user).of_type("User!")
  end
end
