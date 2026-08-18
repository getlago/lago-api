# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::RefreshAllService do
  subject(:result) { described_class.call(owner:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:plan) { create(:plan, organization:) }

  before { create(:subscription, organization:, customer:, plan:, status: :active) }

  context "when the owner is a plan" do
    let(:owner) { plan }

    it "enqueues one job per subscription of the plan" do
      expect { result }.to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.enqueued_count).to eq(1)
    end
  end

  context "when the owner is a customer" do
    let(:owner) { customer }

    it "enqueues one job per subscription of the customer" do
      expect(result.enqueued_count).to eq(1)
    end
  end

  context "when the owner is a billing entity" do
    let(:owner) { billing_entity }

    it "enqueues one job per subscription of its customers" do
      expect(result.enqueued_count).to eq(1)
    end
  end

  context "with pending and canceled subscriptions" do
    let(:owner) { plan }

    before do
      create(:subscription, :pending, organization:, customer:, plan:)
      create(:subscription, :canceled, organization:, customer:, plan:)
    end

    it "skips them" do
      expect(result.enqueued_count).to eq(1)
    end
  end

  context "when the feature flag is disabled" do
    let(:organization) { create(:organization, feature_flags: []) }
    let(:owner) { plan }

    it "enqueues nothing" do
      expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.enqueued_count).to eq(0)
    end
  end

  context "when the owner is not supported" do
    let(:owner) { organization }

    it "raises" do
      expect { result }.to raise_error(ArgumentError, /unsupported owner/)
    end
  end
end
