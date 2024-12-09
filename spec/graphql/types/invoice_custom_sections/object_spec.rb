# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::InvoiceCustomSections::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:organization).of_type('Organization') }

  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:description).of_type('String') }
  it { is_expected.to have_field(:details).of_type('String') }
  it { is_expected.to have_field(:display_name).of_type('String') }
  it { is_expected.to have_field(:name).of_type('String!') }

  it { is_expected.to have_field(:selected).of_type('Boolean!') }
end
