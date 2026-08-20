# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::RefreshAllService do
  subject(:result) { described_class.call(owner:, cursor:) }

  let(:cursor) { nil }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:plan) { create(:plan, organization:) }

  before { create(:subscription, organization:, customer:, plan:, status: :active) }

  context "when the owner is a customer" do
    let(:owner) { customer }

    it "enqueues one job per subscription of the customer" do
      expect { result }.to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.enqueued_count).to eq(1)
    end
  end

  context "when the owner is a billing entity" do
    let(:owner) { billing_entity }

    it "enqueues one job per subscription of its customers" do
      expect(result.enqueued_count).to eq(1)
    end
  end

  # The writer skips a subscription terminated longer ago than its grace period, so a job for one
  # would load it and return.
  context "with terminated subscriptions" do
    let(:owner) { customer }

    before do
      create(
        :subscription,
        organization:, customer:, plan:,
        status: :terminated,
        terminated_at: Subscriptions::BillingPeriods::UpsertService::TERMINATED_GRACE_PERIOD.ago + 1.day
      )
      create(
        :subscription,
        organization:, customer:, plan:,
        status: :terminated,
        terminated_at: Subscriptions::BillingPeriods::UpsertService::TERMINATED_GRACE_PERIOD.ago - 1.day
      )
    end

    it "keeps the ones terminated within the grace period" do
      expect(result.enqueued_count).to eq(2)
    end
  end

  context "with pending and canceled subscriptions" do
    let(:owner) { customer }

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
    let(:owner) { customer }

    it "enqueues nothing" do
      expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
      expect(result.enqueued_count).to eq(0)
    end
  end

  describe "paging" do
    let(:owner) { billing_entity }
    let(:ids) { Subscription.order(:id).pluck(:id) }

    before { create(:subscription, organization:, customer:, plan:, status: :active) }

    context "when a page is full" do
      before { stub_const("#{described_class}::BATCH_SIZE", 1) }

      it "enqueues that page and hands back the cursor to resume from" do
        expect(result.enqueued_count).to eq(1)
        expect(result.next_cursor).to eq(ids.first)

        expect(Subscriptions::BillingPeriods::UpsertJob).to have_been_enqueued.with(ids.first)
        expect(Subscriptions::BillingPeriods::UpsertJob).not_to have_been_enqueued.with(ids.last)
      end

      context "with a cursor" do
        let(:cursor) { ids.first }

        it "resumes after it" do
          expect(result.enqueued_count).to eq(1)

          expect(Subscriptions::BillingPeriods::UpsertJob).to have_been_enqueued.with(ids.last)
          expect(Subscriptions::BillingPeriods::UpsertJob).not_to have_been_enqueued.with(ids.first)
        end
      end
    end

    # A page that is not full is the last one, so paging past it would cost a query returning
    # nothing.
    context "when the page is not full" do
      it "hands back no cursor" do
        expect(result.enqueued_count).to eq(2)
        expect(result.next_cursor).to be_nil
      end
    end

    context "when the cursor is past the last subscription" do
      let(:cursor) { ids.last }

      it "enqueues nothing" do
        expect { result }.not_to have_enqueued_job(Subscriptions::BillingPeriods::UpsertJob)
        expect(result.enqueued_count).to eq(0)
        expect(result.next_cursor).to be_nil
      end
    end
  end

  # A plan moves the boundaries of its subscriptions, but a plan attached to one refuses the
  # attributes that would, so it is not an owner here.
  context "when the owner is not supported" do
    let(:owner) { plan }

    it "raises" do
      expect { result }.to raise_error(ArgumentError, /unsupported owner/)
    end
  end
end
