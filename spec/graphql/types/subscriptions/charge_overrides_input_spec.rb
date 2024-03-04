# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Subscriptions::ChargeOverridesInput do
  subject { described_class }

  it { is_expected.to accept_argument(:billable_metric_id).of_type('ID!') }
  it { is_expected.to accept_argument(:id).of_type('ID!') }
  it { is_expected.to accept_argument(:filters).of_type('[ChargeFilterInput!]') }
  it { is_expected.to accept_argument(:group_properties).of_type('[GroupPropertiesInput!]') }
  it { is_expected.to accept_argument(:invoice_display_name).of_type('String') }
  it { is_expected.to accept_argument(:min_amount_cents).of_type('BigInt') }
  it { is_expected.to accept_argument(:properties).of_type('PropertiesInput') }
  it { is_expected.to accept_argument(:tax_codes).of_type('[String!]') }
end
