# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::FixedCharges::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:invoice_display_name).of_type("String") }

  it { is_expected.to have_field(:add_on).of_type("AddOn!") }
  it { is_expected.to have_field(:charge_model).of_type("FixedChargeChargeModelEnum!") }
  it { is_expected.to have_field(:pay_in_advance).of_type("Boolean!") }
  it { is_expected.to have_field(:properties).of_type("FixedChargeProperties") }
  it { is_expected.to have_field(:prorated).of_type("Boolean!") }

  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:deleted_at).of_type("ISO8601DateTime") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }

  it { is_expected.to have_field(:taxes).of_type("[Tax!]") }
end
