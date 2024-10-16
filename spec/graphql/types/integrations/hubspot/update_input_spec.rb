# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Hubspot::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID') }
  it { is_expected.to accept_argument(:code).of_type('String') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:connection_id).of_type('String') }
  it { is_expected.to accept_argument(:default_targeted_object).of_type('HubspotTargetedObjectsEnum') }
  it { is_expected.to accept_argument(:sync_invoices).of_type('Boolean') }
  it { is_expected.to accept_argument(:sync_subscriptions).of_type('Boolean') }
end
