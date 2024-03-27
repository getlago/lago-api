# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Charges::GroupProperties do
  subject { described_class }

  it { is_expected.to have_field(:group_id).of_type("ID!") }
  it { is_expected.to have_field(:invoice_display_name).of_type("String") }
  it { is_expected.to have_field(:values).of_type("Properties!") }
  it { is_expected.to have_field(:deleted_at).of_type("ISO8601DateTime") }
end
