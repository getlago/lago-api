# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::ChargeFilters::Input do
  subject { described_class }

  it { is_expected.to accept_argument(:invoice_display_name).of_type("String") }
  it { is_expected.to accept_argument(:properties).of_type("PropertiesInput!") }
  it { is_expected.to accept_argument(:values).of_type("ChargeFilterValues!") }
end
