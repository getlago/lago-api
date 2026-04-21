# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::CloneInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:id).of_type("ID!")
  end
end
