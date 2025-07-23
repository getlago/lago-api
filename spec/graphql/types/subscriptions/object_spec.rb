# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Subscriptions::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:customer).of_type("Customer!")
    expect(subject).to have_field(:external_id).of_type("String!")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:plan).of_type("Plan!")

    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:next_name).of_type("String")
    expect(subject).to have_field(:period_end_date).of_type("ISO8601Date")
    expect(subject).to have_field(:status).of_type("StatusTypeEnum")

    expect(subject).to have_field(:billing_time).of_type("BillingTimeEnum")
    expect(subject).to have_field(:canceled_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:ending_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:started_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:subscription_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:terminated_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:on_termination_credit_note).of_type("OnTerminationCreditNoteEnum")
    expect(subject).to have_field(:on_termination_invoice).of_type("OnTerminationInvoiceEnum!")

    expect(subject).to have_field(:current_billing_period_started_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:current_billing_period_ending_at).of_type("ISO8601DateTime")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")

    expect(subject).to have_field(:next_plan).of_type("Plan")
    expect(subject).to have_field(:next_subscription).of_type("Subscription")
    expect(subject).to have_field(:next_subscription_type).of_type("NextSubscriptionTypeEnum")
    expect(subject).to have_field(:next_subscription_at).of_type("ISO8601DateTime")

    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")
    expect(subject).to have_field(:fees).of_type("[Fee!]")

    expect(subject).to have_field(:lifetime_usage).of_type("SubscriptionLifetimeUsage")
  end
end
