# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Orders::ExecutionRecord do
  subject { described_class }

  it do
    expect(subject).to have_field(:errors).of_type("[String!]!")
    expect(subject).to have_field(:executed_at).of_type("String")
    expect(subject).to have_field(:execution_mode).of_type("OrderExecutionModeEnum")
    expect(subject).to have_field(:invoice_id).of_type("ID")
  end
end
