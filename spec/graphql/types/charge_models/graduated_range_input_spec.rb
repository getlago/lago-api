# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::ChargeModels::GraduatedRangeInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:from_value).of_type("BigInt!")
    expect(subject).to accept_argument(:to_value).of_type("BigInt")

    expect(subject).to accept_argument(:flat_amount).of_type("String!")
    expect(subject).to accept_argument(:per_unit_amount).of_type("String!")
  end
end


