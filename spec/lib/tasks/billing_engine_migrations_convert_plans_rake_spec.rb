# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:convert_plans" do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let_it_be(:plan) do
    create(:plan, organization:, code: "pro_monthly", amount_cents: 10_000, amount_currency: "EUR", trial_period: 14)
  end
  let_it_be(:charge) do
    create(:standard_charge, plan:, billable_metric:, code: "calls", invoice_display_name: nil, properties: {amount: "0.5"})
  end

  let(:task) { Rake::Task["billing_engine_migrations:convert_plans"] }
  let(:status) { "shadowing" }
  let(:shadow_organization) { create(:organization) }

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:billable_metric, organization: shadow_organization, code: "api_calls")
    create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping: {"pro_monthly" => "pro_v2"})
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

    it "aborts without converting anything" do
      expect { task.invoke(organization.id) }.to raise_error(SystemExit).and output(/not shadowing/).to_stderr

      expect(shadow_organization.catalog_plans).to be_empty
    end
  end

  context "when DRY_RUN is enabled (default)" do
    it "lists the rate cards it would create and the unmapped fields, and writes nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[DRY RUN] plan pro_monthly -> pro_v2: would_create",
          "rate_card pro_v2_subscription_fee: product pro_v2_subscription_fee (fixed), standard arrears every 1 month, " \
            "properties {\"amount\":\"100.0\"}, units 1.0",
          "rate_card pro_v2_calls: product api_calls (metered), standard arrears every 1 month, properties {\"amount\":\"0.5\"",
          "not implemented: trial_period",
          "Done [DRY RUN]: 1 would_create"
        )
      ).to_stdout

      expect(shadow_organization.catalog_plans).to be_empty
      expect(shadow_organization.products).to be_empty
    end
  end

  context "when DRY_RUN is disabled" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "creates the catalog plans, then skips them on the next run" do
      expect { task.invoke(organization.id) }.to output(/Done \[LIVE\]: 1 created/).to_stdout

      expect(shadow_organization.catalog_plans.pluck(:code)).to eq(["pro_v2"])
      expect(shadow_organization.rate_cards.pluck(:code)).to match_array(%w[pro_v2_subscription_fee pro_v2_calls])

      task.reenable
      expect { task.invoke(organization.id) }.to output(/Done \[LIVE\]: 1 skipped/).to_stdout
      expect(shadow_organization.rate_cards.count).to eq(2)
    end

    context "when a plan fails" do
      before { shadow_organization.billable_metrics.find_by!(code: "api_calls").discard! }

      it "lists the error and aborts" do
        expect { task.invoke(organization.id) }
          .to raise_error(SystemExit, /1 plan\(s\) failed/)
          .and output(/plan pro_monthly -> pro_v2: failed \(billable_metrics_not_copied: api_calls\)/).to_stdout
      end
    end
  end
end
