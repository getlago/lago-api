# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Charges::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:invoice_display_name).of_type("String") }
  it { is_expected.to have_field(:billable_metric).of_type("BillableMetric!") }
  it { is_expected.to have_field(:charge_model).of_type("ChargeModelEnum!") }
  it { is_expected.to have_field(:group_properties).of_type("[GroupProperties!]") }
  it { is_expected.to have_field(:invoiceable).of_type("Boolean!") }
  it { is_expected.to have_field(:min_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:pay_in_advance).of_type("Boolean!") }
  it { is_expected.to have_field(:properties).of_type("Properties") }
  it { is_expected.to have_field(:prorated).of_type("Boolean!") }
  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:deleted_at).of_type("ISO8601DateTime") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:taxes).of_type("[Tax!]") }
  it { is_expected.to have_field(:filters).of_type("[ChargeFilter!]") }
end
