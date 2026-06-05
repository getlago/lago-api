# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::FinanceAssistant::Answer do
  subject { described_class }

  it do
    expect(subject).to have_field(:explanation).of_type("String!")
    expect(subject).to have_field(:results).of_type("String!")
    expect(subject).to have_field(:session_expired).of_type("Boolean!")
    expect(subject).to have_field(:session_id).of_type("ID!")
    expect(subject).to have_field(:sql_query).of_type("String")
  end
end
