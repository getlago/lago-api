# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::FinanceAssistant::Export do
  subject { described_class }

  it do
    expect(subject).to have_field(:content).of_type("String!")
    expect(subject).to have_field(:filename).of_type("String!")
    expect(subject).to have_field(:row_count).of_type("Int!")
    expect(subject).to have_field(:truncated).of_type("Boolean!")
  end
end
