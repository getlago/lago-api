# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::PlanSubscriptionsCount do
  subject(:counts) { described_class.new(kind, organization.id).fetch(plan_ids) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:overridden_plan) { create(:plan, organization:, parent: plan) }
  let(:plan_ids) { [plan.id] }

  describe "#initialize" do
    it "rejects an unknown kind" do
      expect { described_class.new(:unknown, organization.id) }.to raise_error(ArgumentError, "unknown kind: unknown")
    end
  end

  describe "#fetch" do
    context "with :subscriptions" do
      let(:kind) { :subscriptions }
      let(:other_plan) { create(:plan, organization:) }
      let(:plan_ids) { [plan.id, other_plan.id] }

      before do
        create(:subscription, plan:, customer:)
        create(:subscription, :terminated, plan: overridden_plan, customer:)
        create(:subscription, plan: create(:plan, organization:, parent: plan, deleted_at: Time.current), customer:)
        create(:subscription)
      end

      it "counts every subscription of the plan and its kept overrides, zero when there is none" do
        expect(counts).to eq([2, 0])
      end
    end

    context "with :active_subscriptions" do
      let(:kind) { :active_subscriptions }

      context "when the plan has overrides" do
        before do
          create_list(:subscription, 2, plan:, customer:)
          create_list(:subscription, 3, plan: overridden_plan, customer:)
          create(:subscription, plan: create(:plan, organization:, parent: plan), customer:)
        end

        it "counts active subscriptions on the plan and all its overrides" do
          expect(counts).to eq([6])
        end
      end

      context "with subscriptions that are not active" do
        before do
          [plan, overridden_plan].each do |subscription_plan|
            create(:subscription, plan: subscription_plan, customer:)
            %i[pending terminated canceled incomplete].each do |status|
              create(:subscription, status, plan: subscription_plan, customer:)
            end
          end
        end

        it "counts only the active ones" do
          expect(counts).to eq([2])
        end
      end

      context "with discarded overrides and unrelated plans" do
        before do
          discarded_override = create(:plan, organization:, parent: plan, deleted_at: Time.current)
          unrelated_plan = create(:plan, organization:)
          [discarded_override, unrelated_plan].each do |subscription_plan|
            create(:subscription, plan: subscription_plan, customer:)
          end
          create(:subscription)
        end

        it "does not count their subscriptions" do
          expect(counts).to eq([0])
        end
      end

      context "when an override and its parent are loaded together" do
        let(:plan_ids) { [plan.id, overridden_plan.id] }

        before do
          create(:subscription, plan:, customer:)
          create_list(:subscription, 2, plan: overridden_plan, customer:)
          create(:subscription, plan: create(:plan, organization:, parent: plan), customer:)
        end

        it "counts the override on its own and within its parent" do
          expect(counts).to eq([4, 2])
        end
      end

      context "when the plan is discarded" do
        let(:plan) { create(:plan, organization:, deleted_at: Time.current) }

        before { create(:subscription, plan:, customer:) }

        it "still counts its subscriptions" do
          expect(counts).to eq([1])
        end
      end
    end

    context "with :customers" do
      let(:kind) { :customers }
      let(:other_customer) { create(:customer, organization:) }

      before do
        create(:subscription, plan:, customer:)
        create(:subscription, plan: overridden_plan, customer:)
        create(:subscription, plan: overridden_plan, customer: other_customer)
        create(:subscription, :terminated, plan:, customer: create(:customer, organization:))
      end

      it "counts each customer with an active subscription once across the plan and its overrides" do
        expect(counts).to eq([2])
      end
    end

    context "with :draft_invoices" do
      let(:kind) { :draft_invoices }

      context "with draft invoices on the plan and its overrides" do
        before do
          [plan, overridden_plan].each do |invoice_plan|
            subscription = create(:subscription, plan: invoice_plan, customer:)
            create(:invoice_subscription, invoice: create(:invoice, :draft, customer:, organization:), subscription:)
          end
        end

        it "counts them all" do
          expect(counts).to eq([2])
        end
      end

      context "with an invoice shared by the plan and its overrides" do
        before do
          invoice = create(:invoice, :draft, customer:, organization:)
          [plan, overridden_plan, create(:plan, organization:, parent: plan)].each do |invoice_plan|
            subscription = create(:subscription, plan: invoice_plan, customer:)
            create(:invoice_subscription, invoice:, subscription:)
          end
        end

        it "counts it once" do
          expect(counts).to eq([1])
        end
      end

      context "with finalized invoices and discarded overrides" do
        before do
          [plan, overridden_plan].each do |invoice_plan|
            subscription = create(:subscription, plan: invoice_plan, customer:)
            create(:invoice_subscription, invoice: create(:invoice, status: :finalized, customer:, organization:), subscription:)
          end
          discarded_plan = create(:plan, organization:, parent: plan, deleted_at: Time.current)
          subscription = create(:subscription, plan: discarded_plan, customer:)
          create(:invoice_subscription, invoice: create(:invoice, :draft, customer:, organization:), subscription:)
        end

        it "does not count them" do
          expect(counts).to eq([0])
        end
      end

      context "with an invoice of another organization" do
        before do
          invoice = create(:invoice, :draft, organization: create(:organization))
          subscription = create(:subscription, plan:, customer:)
          create(:invoice_subscription, invoice:, subscription:)
        end

        it "does not count it" do
          expect(counts).to eq([0])
        end
      end
    end
  end
end
