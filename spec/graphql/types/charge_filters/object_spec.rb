# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::ChargeFilters::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:invoice_display_name).of_type("String") }
  it { is_expected.to have_field(:properties).of_type("Properties!") }
  it { is_expected.to have_field(:values).of_type("ChargeFilterValues!") }
end
