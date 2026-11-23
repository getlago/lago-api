# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:backfill_subscriptions" do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:other_plan) { create(:plan, organization:) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:other_customer) { create(:customer, organization:) }
  let_it_be(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

  let(:task) { Rake::Task["billing_engine_migrations:backfill_subscriptions"] }
  let(:env) { {} }
  let(:status) { "shadowing" }
  let(:migration) do
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      status:,
      plan_mapping: {plan.code => "catalog_plan"}
    )
  end

  let(:eligible_subscriptions) { create_list(:subscription, 2, organization:, customer:, plan:) }

  let(:override_subscription) do
    create(:subscription, organization:, customer:, plan: create(:plan, organization:, code: plan.code, parent: plan))
  end

  let(:ended_subscription) { create(:subscription, organization:, customer:, plan:, ending_at: 1.day.ago) }

  let(:copied_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create_shadow_contract(external_id: subscription.external_id, code: subscription.id)
    end
  end

  let(:taken_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create_shadow_contract(external_id: subscription.external_id, code: "other-subscription-id")
    end
  end

  let(:ended_copy_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create_shadow_contract(:terminated, external_id: subscription.external_id, code: subscription.id)
    end
  end

  let(:recopiable_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create_shadow_contract(:terminated, external_id: subscription.external_id, code: "previous-subscription-id")
    end
  end

  let(:subscription_with_contract_elsewhere) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create(:contract, external_id: subscription.external_id, code: subscription.id)
    end
  end

  let(:customer_subscriptions_to_copy) do
    eligible_subscriptions + [recopiable_subscription, subscription_with_contract_elsewhere]
  end

  let(:other_customer_subscription) { create(:subscription, organization:, customer: other_customer, plan:) }
  let(:subscriptions_to_copy) { customer_subscriptions_to_copy + [other_customer_subscription] }

  def create_shadow_contract(*traits, external_id:, code:)
    create(:contract, *traits, organization: shadow_organization, customer: shadow_customer, external_id:, code:)
  end

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable
    stub_const("ENV", ENV.to_h.merge(env))

    migration
    subscriptions_to_copy
    override_subscription
    ended_subscription
    copied_subscription
    taken_subscription
    ended_copy_subscription
    create(:subscription, organization:, customer:, plan: other_plan)
    create(:subscription, :terminated, organization:, customer:, plan:)
  end

  context "without an organization_id argument" do
    it "aborts with a usage message" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Missing organization_id argument/).to_stderr
    end
  end

  context "when the organization has no migration" do
    it "aborts" do
      expect { task.invoke(create(:organization).id) }
        .to raise_error(SystemExit).and output(/No billing engine migration/).to_stderr
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "aborts without enqueuing anything" do
      expect { task.invoke(organization.id) }.to raise_error(SystemExit).and output(/not shadowing/).to_stderr

      expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).not_to have_been_enqueued
    end
  end

  context "when the shadow organization has a webhook endpoint" do
    before { create(:webhook_endpoint, organization: shadow_organization) }

    it "aborts without enqueuing anything" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit)
        .and output(/has webhook endpoints, invoice emails or a dunning campaign/).to_stderr

      expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).not_to have_been_enqueued
    end
  end

  context "when CUSTOMERS_PER_MINUTE is not a positive integer" do
    let(:env) { {"CUSTOMERS_PER_MINUTE" => "0"} }

    it "aborts" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit).and output(/CUSTOMERS_PER_MINUTE must be a positive integer/).to_stderr
    end
  end

  context "when AFTER_CUSTOMER_ID is not a customer id" do
    let(:env) { {"AFTER_CUSTOMER_ID" => "abc"} }

    it "aborts" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit).and output(/AFTER_CUSTOMER_ID must be a customer id/).to_stderr
    end
  end

  context "when LIMIT is not a positive integer" do
    let(:env) { {"LIMIT" => "many"} }

    it "aborts" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit).and output(/LIMIT must be a positive integer/).to_stderr
    end
  end

  context "when DRY_RUN is enabled (default)" do
    it "lists the subscriptions to copy and to skip with the reason, and enqueues nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          *subscriptions_to_copy.map { |subscription| "[DRY RUN] would copy subscription #{subscription.external_id}" },
          "[DRY RUN] would skip subscription #{override_subscription.external_id} (plan_override_not_supported)",
          "[DRY RUN] would skip subscription #{ended_subscription.external_id} (already_ended)",
          "[DRY RUN] would skip subscription #{copied_subscription.external_id} (already_copied)",
          "[DRY RUN] would skip subscription #{taken_subscription.external_id} (external_id_taken_by_other_subscription)",
          "[DRY RUN] would skip subscription #{ended_copy_subscription.external_id} (shadow_contract_ended)",
          "Would enqueue 5 subscription(s) of 2 customer(s) over 1 minute(s), skipped 5 " \
          "(already_copied: 1, already_ended: 1, external_id_taken_by_other_subscription: 1, " \
          "plan_override_not_supported: 1, shadow_contract_ended: 1) [DRY RUN]"
        )
      ).to_stdout

      expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).not_to have_been_enqueued
    end
  end

  context "when DRY_RUN is disabled" do
    let(:env) { {"DRY_RUN" => "false", "CUSTOMERS_PER_MINUTE" => "1"} }
    let(:customers_in_order) { [customer, other_customer].sort_by(&:id) }

    def subscription_ids_of(owner)
      subscriptions_to_copy.select { |subscription| subscription.customer_id == owner.id }.map(&:id)
    end

    it "enqueues one job per customer, spread at the given rate, and lists the skipped subscriptions" do
      freeze_time do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            "[LIVE] skipped subscription #{copied_subscription.external_id} (already_copied)",
            "Enqueued 5 subscription(s) of 2 customer(s) over 2 minute(s), skipped 5"
          )
        ).to_stdout

        first_customer, second_customer = customers_in_order
        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
          .to have_been_enqueued.with(migration, match_array(subscription_ids_of(first_customer))).at(Time.current)
        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
          .to have_been_enqueued.with(migration, match_array(subscription_ids_of(second_customer))).at(1.minute.from_now)
        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).to have_been_enqueued.twice
      end
    end

    context "with several customers per minute" do
      let(:env) { {"DRY_RUN" => "false", "CUSTOMERS_PER_MINUTE" => "2"} }

      it "spreads the customers evenly over the minute" do
        freeze_time do
          expect { task.invoke(organization.id) }.to output(a_string_including("over 1 minute(s)")).to_stdout

          first_customer, second_customer = customers_in_order
          expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
            .to have_been_enqueued.with(migration, match_array(subscription_ids_of(first_customer))).at(Time.current)
          expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
            .to have_been_enqueued.with(migration, match_array(subscription_ids_of(second_customer))).at(30.seconds.from_now)
        end
      end
    end

    context "with AFTER_CUSTOMER_ID" do
      let(:env) { {"DRY_RUN" => "false", "AFTER_CUSTOMER_ID" => customers_in_order.first.id} }

      it "only processes the customers after it" do
        expect { task.invoke(organization.id) }.to output(a_string_including("of 1 customer(s)")).to_stdout

        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
          .to have_been_enqueued.with(migration, match_array(subscription_ids_of(customers_in_order.last)))
        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).to have_been_enqueued.once
      end
    end

    context "with a LIMIT" do
      let(:env) { {"DRY_RUN" => "false", "LIMIT" => "1"} }

      it "stops after that number of customers and prints where to resume" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            "Enqueued",
            "of 1 customer(s)",
            "Stopped at 1 customer(s)",
            "AFTER_CUSTOMER_ID=#{customers_in_order.first.id}"
          )
        ).to_stdout

        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob)
          .to have_been_enqueued.with(migration, match_array(subscription_ids_of(customers_in_order.first)))
        expect(BillingEngineMigrations::CopyCustomerSubscriptionsJob).to have_been_enqueued.once
      end
    end
  end
end
