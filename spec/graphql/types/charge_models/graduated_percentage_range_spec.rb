# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::ChargeModels::GraduatedPercentageRange, type: :graphql do
  let(:object) { described_class }

  it { expect(object).to have_field(:from_value).of_type("BigInt!") }
  it { expect(object).to have_field(:to_value).of_type("BigInt") }
  it { expect(object).to have_field(:flat_amount).of_type("String!") }
  it { expect(object).to have_field(:rate).of_type("String!") }
end
