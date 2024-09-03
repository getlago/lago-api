# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Subscriptions::Object do
  subject { described_class }

  it { is_expected.to have_field(:customer).of_type('Customer!') }
  it { is_expected.to have_field(:external_id).of_type('String!') }
  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:plan).of_type('Plan!') }

  it { is_expected.to have_field(:name).of_type('String') }
  it { is_expected.to have_field(:next_name).of_type('String') }
  it { is_expected.to have_field(:next_pending_start_date).of_type('ISO8601Date') }
  it { is_expected.to have_field(:period_end_date).of_type('ISO8601Date') }
  it { is_expected.to have_field(:status).of_type('StatusTypeEnum') }

  it { is_expected.to have_field(:billing_time).of_type('BillingTimeEnum') }
  it { is_expected.to have_field(:canceled_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:ending_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:started_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:subscription_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:terminated_at).of_type('ISO8601DateTime') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }

  it { is_expected.to have_field(:next_plan).of_type('Plan') }
  it { is_expected.to have_field(:next_subscription).of_type('Subscription') }

  it { is_expected.to have_field(:fees).of_type('[Fee!]') }

  it { is_expected.to have_field(:lifetime_usage).of_type('SubscriptionLifetimeUsage') }
end
