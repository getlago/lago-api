# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CustomerSnapshots::Object do
  subject { described_class }

  it { expect(subject).to have_field(:display_name).of_type("String") }
  it { expect(subject).to have_field(:firstname).of_type("String") }
  it { expect(subject).to have_field(:lastname).of_type("String") }
  it { expect(subject).to have_field(:email).of_type("String") }
  it { expect(subject).to have_field(:phone).of_type("String") }
  it { expect(subject).to have_field(:url).of_type("String") }
  it { expect(subject).to have_field(:tax_identification_number).of_type("String") }
  it { expect(subject).to have_field(:applicable_timezone).of_type("String") }
  it { expect(subject).to have_field(:address_line1).of_type("String") }
  it { expect(subject).to have_field(:address_line2).of_type("String") }
  it { expect(subject).to have_field(:city).of_type("String") }
  it { expect(subject).to have_field(:state).of_type("String") }
  it { expect(subject).to have_field(:zipcode).of_type("String") }
  it { expect(subject).to have_field(:country).of_type("String") }
  it { expect(subject).to have_field(:legal_name).of_type("String") }
  it { expect(subject).to have_field(:legal_number).of_type("String") }
  it { expect(subject).to have_field(:shipping_address).of_type("CustomerAddress") }
end
