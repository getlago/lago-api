# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Hubspot do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }

  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:connection_id).of_type('ID!') }
  it { is_expected.to have_field(:default_targeted_object).of_type('HubspotTargetedObjectsEnum!') }
  it { is_expected.to have_field(:name).of_type('String!') }

  it { is_expected.to have_field(:sync_invoices).of_type('Boolean') }
  it { is_expected.to have_field(:sync_subscriptions).of_type('Boolean') }
end
