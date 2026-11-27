# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::DestroyService do
  subject(:destroy_service) { described_class.new(plan:) }

  let(:organization) { create_default(:organization) }
  let(:plan) { create(:plan, organization:, pending_deletion: true) }
  let(:membership) { create(:membership) }

  before do
    plan
  end

  describe "#call" do
    it "soft deletes the plan" do
      freeze_time do
        expect { destroy_service.call }.to change(Plan, :count).by(-1)
          .and change { plan.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "sets pending_deletion to false" do
      expect { destroy_service.call }.to change { plan.reload.pending_deletion }.from(true).to(false)
    end

    it "produces an activity log" do
      described_class.call(plan:)

      expect(Utils::ActivityLog).to have_produced("plan.deleted").after_commit.with(plan)
    end

    context "when plan is not found" do
      let(:plan) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with active subscriptions" do
      let(:subscriptions) { create_list(:subscription, 2, plan:) }

      before { subscriptions }

      it "terminates the subscriptions" do
        result = destroy_service.call

        expect(result).to be_success

        subscriptions.each do |subscription|
          expect(subscription.reload).to be_terminated
        end
      end
    end

    context "with pending subscriptions" do
      let(:subscriptions) { create_list(:subscription, 2, :pending, plan:) }

      before { subscriptions }

      it "cancels the subscriptions" do
        result = destroy_service.call

        expect(result).to be_success

        subscriptions.each do |subscription|
          expect(subscription.reload).to be_canceled
        end
      end
    end

    context "with draft invoices" do
      let(:subscription) { create(:subscription, plan:) }
      let(:invoices) { create_list(:invoice, 2, :draft) }

      before do
        create(:invoice_subscription, invoice: invoices.first, subscription:, invoicing_reason: :subscription_starting)
        create(:invoice_subscription, invoice: invoices.second, subscription:, invoicing_reason: :subscription_periodic)
      end

      it "finalizes draft invoices" do
        result = destroy_service.call

        expect(result).to be_success

        invoices.each do |invoice|
          expect(invoice.reload).to be_finalized
        end
      end
    end

    context "with entitlements" do
      let(:entitlement) { create(:entitlement, plan:) }
      let(:entitlement_value) { create(:entitlement_value, entitlement: entitlement, privilege: create(:privilege, feature: entitlement.feature)) }

      before do
        entitlement
        entitlement_value
      end

      it "destroys the entitlements" do
        destroy_service.call
        expect(entitlement.reload).to be_discarded
        expect(entitlement_value.reload).to be_discarded
        expect(entitlement.updated_at).to eq(entitlement.deleted_at)
        expect(entitlement_value.updated_at).to eq(entitlement_value.deleted_at)
      end
    end

    context "when another connection holds the plan lock", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      # Frees the lock holder left waiting by a failed expectation.
      after { release << -> {} }

      it "waits for the lock, then discards the entitlement written under it" do
        holder = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              Plan.lock("FOR NO KEY UPDATE").find(plan.id)
              locked << true
              release.pop.call
            end
          end
        end
        locked.pop

        destroyer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(plan: Plan.find(plan.id))
          end
        end
        expect(destroyer.join(0.5)).to be_nil

        # The holder commits an entitlement that the deletion can only see once it has the lock.
        release << -> { create(:entitlement, plan:, organization:) }
        holder.join

        expect(destroyer.value).to be_success
        expect(Plan.with_discarded.find(plan.id)).to be_discarded
        expect(Entitlement::Entitlement.unscoped.where(plan_id: plan.id).sole).to be_discarded
      end
    end

    context "when plan is already discarded" do
      let(:plan) { create(:plan, :deleted, organization:) }

      it "returns the deleted plan" do
        result = destroy_service.call

        expect(result).to be_success
        expect(result.plan).to eq(plan)
      end
    end
  end
end
