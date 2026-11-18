# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Auth::Google::AuthUrl do
  subject { described_class }

  it do
    expect(subject).to have_field(:state_secret).of_type("String")
    expect(subject).to have_field(:url).of_type("String!")
  end
end
