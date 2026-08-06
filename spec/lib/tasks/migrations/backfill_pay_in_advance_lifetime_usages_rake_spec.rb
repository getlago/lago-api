# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:backfill_pay_in_advance_lifetime_usages" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_pay_in_advance_lifetime_usages"] }

  let(:organization) { create(:organization, premium_integrations: ["lifetime_usage"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:lifetime_usage) { create(:lifetime_usage, organization:, subscription:, recalculate_invoiced_usage: false) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  before do
    Rake.application.rake_require("tasks/migrations/backfill_pay_in_advance_lifetime_usages")
    Rake::Task.define_task(:environment)
    task.reenable

    lifetime_usage
    create(:invoice_subscription, invoice:, subscription:, invoicing_reason: :in_advance_charge)

    allow($stdout).to receive(:puts)
  end

  it "does not flag anything by default" do
    task.invoke

    expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
  end

  context "when DRY_RUN is false" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
      ENV.delete("DRY_RUN")
    end

    it "flags the lifetime usage for recalculation" do
      task.invoke

      expect(lifetime_usage.reload.recalculate_invoiced_usage).to be true
    end

    context "when the organization has no lifetime usage integration" do
      let(:organization) { create(:organization, premium_integrations: []) }

      it "does not flag the lifetime usage" do
        task.invoke

        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
      end
    end

    context "when the subscription is terminated" do
      let(:subscription) { create(:subscription, :terminated, customer:, organization:) }

      it "does not flag the lifetime usage" do
        task.invoke

        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
      end
    end

    context "when the subscription has no in_advance_charge invoice" do
      before do
        InvoiceSubscription.update_all(invoicing_reason: :subscription_periodic) # rubocop:disable Rails/SkipsModelValidations
      end

      it "does not flag the lifetime usage" do
        task.invoke

        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be false
      end
    end
  end
end
