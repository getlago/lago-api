# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:backfill_shared_invoice_lifetime_usages" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_shared_invoice_lifetime_usages"] }

  let(:organization) { create(:organization, premium_integrations: ["lifetime_usage"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:lifetime_usage) { create(:lifetime_usage, organization:, subscription:, recalculate_invoiced_usage: false) }

  before do
    Rake.application.rake_require("tasks/migrations/backfill_shared_invoice_lifetime_usages")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  around do |example|
    previous = ENV.values_at("DRY_RUN", "ORGANIZATION_ID")
    example.run
    ENV["DRY_RUN"], ENV["ORGANIZATION_ID"] = previous
  end

  context "when the subscription shares an invoice with another subscription" do
    let(:other_subscription) { create(:subscription, customer:, organization:) }

    before do
      create(
        :invoice,
        :finalized,
        :with_subscriptions,
        customer:,
        organization:,
        subscriptions: [subscription, other_subscription]
      )
      lifetime_usage
    end

    it "reports the lifetime usage without flagging it in dry-run" do
      ENV["DRY_RUN"] = "true"

      expect { task.invoke }.to output(/would be flagged for recalculation: 1/).to_stdout
      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
    end

    it "flags the lifetime usage for recalculation" do
      ENV["DRY_RUN"] = "false"

      expect { task.invoke }.to output(/Done/).to_stdout
      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be true
    end
  end

  context "when the subscription is alone on its invoice" do
    before do
      create(:invoice, :finalized, :with_subscriptions, customer:, organization:, subscriptions: [subscription])
      lifetime_usage
    end

    it "does not flag the lifetime usage" do
      ENV["DRY_RUN"] = "false"

      expect { task.invoke }.to output(/Nothing to flag/).to_stdout
      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
    end
  end

  context "when the organization is restricted with ORGANIZATION_ID" do
    let(:other_organization) { create(:organization, premium_integrations: ["lifetime_usage"]) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_org_subscription) { create(:subscription, customer: other_customer, organization: other_organization) }
    let(:other_org_lifetime_usage) do
      create(:lifetime_usage, organization: other_organization, subscription: other_org_subscription, recalculate_invoiced_usage: false)
    end

    before do
      create(
        :invoice,
        :finalized,
        :with_subscriptions,
        customer:,
        organization:,
        subscriptions: [subscription, create(:subscription, customer:, organization:)]
      )
      create(
        :invoice,
        :finalized,
        :with_subscriptions,
        customer: other_customer,
        organization: other_organization,
        subscriptions: [other_org_subscription, create(:subscription, customer: other_customer, organization: other_organization)]
      )
      lifetime_usage
      other_org_lifetime_usage
    end

    it "only flags the lifetime usages of that organization" do
      ENV["DRY_RUN"] = "false"
      ENV["ORGANIZATION_ID"] = organization.id

      expect { task.invoke }.to output(/Done/).to_stdout
      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be true
      expect(other_org_lifetime_usage.reload.recalculate_invoiced_usage).to be false
    end
  end

  context "when the organization has no lifetime usage or progressive billing support" do
    let(:organization) { create(:organization, premium_integrations: []) }

    before do
      create(
        :invoice,
        :finalized,
        :with_subscriptions,
        customer:,
        organization:,
        subscriptions: [subscription, create(:subscription, customer:, organization:)]
      )
      lifetime_usage
    end

    it "does not flag the lifetime usage" do
      ENV["DRY_RUN"] = "false"

      expect { task.invoke }.to output(/Nothing to flag/).to_stdout
      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
    end
  end
end
