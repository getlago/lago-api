# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:realtime_usage:check_eligibility", :premium do # rubocop:disable RSpec/DescribeClass
  subject(:invoke) { task.invoke }

  let(:task) { Rake::Task["recipes:realtime_usage:check_eligibility"] }
  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  let(:realtime_usage_enabled) { "true" }

  before do
    Rake.application.rake_require("tasks/recipes/realtime_usage")
    Rake::Task.define_task(:environment)
    task.reenable

    ENV["LAGO_REALTIME_USAGE_ENABLED"] = realtime_usage_enabled
    allow(Events::Stores::StoreFactory).to receive(:supports_clickhouse?).and_return(true)
    stub_stdin(organization.id, "y")
  end

  after { ENV["LAGO_REALTIME_USAGE_ENABLED"] = nil }

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  context "when the organization is not found" do
    before { stub_stdin("00000000") }

    it "aborts" do
      expect { invoke }.to raise_error(SystemExit)
    end
  end

  context "when the organization has no active subscription" do
    it "says nothing can be concluded about coverage" do
      expect { invoke }.to output(/No active subscription/).to_stdout
    end
  end

  context "when every charge on the plan is servable" do
    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "reports the organization as a candidate" do
      expect { invoke }.to output(%r{Candidate: 1/1 charges, 1 fully served subscription}).to_stdout
    end
  end

  context "when no charge on the plan is servable" do
    before do
      create(:standard_charge, plan:, billable_metric: create(:max_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "reports the blocking reason" do
      expect { invoke }.to output(/unsupported_aggregation_type/).to_stdout
    end

    it "does not recommend enabling" do
      expect { invoke }.to output(/Not worth enabling/).to_stdout
    end
  end

  context "when the plan mixes servable and delegated charges" do
    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:, recurring: true))
      create(:subscription, customer:, plan:, organization:)
    end

    it "counts the subscription as partly served" do
      expect { invoke }.to output(/partly served:  1/).to_stdout
    end

    it "reports the served share of the charges" do
      expect { invoke }.to output(%r{distinct charges served: 1/2}).to_stdout
    end
  end

  context "when the organization still reads the postgres events store" do
    let(:organization) { create(:organization) }

    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "rules it out whatever its charges look like" do
      expect { invoke }.to output(/Not a candidate: the organization reads the Postgres events store/).to_stdout
    end
  end

  context "when clickhouse is disabled on the deployment" do
    before do
      allow(Events::Stores::StoreFactory).to receive(:supports_clickhouse?).and_return(false)
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "rules out the deployment" do
      expect { invoke }.to output(/Not a candidate: the deployment itself cannot serve the buckets/).to_stdout
    end
  end

  context "when the kill switch is on and the flag is already enabled" do
    let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }

    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "does not recommend enabling a flag that is already on" do
      expect { invoke }.to output(/Already serving: both switches are on/).to_stdout
    end
  end

  context "when the flag is enabled but the kill switch is off" do
    let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
    let(:realtime_usage_enabled) { "false" }

    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "points at the kill switch rather than the flag" do
      expect { invoke }.to output(/the realtime_usage flag is on but LAGO_REALTIME_USAGE_ENABLED is off/).to_stdout
    end
  end

  context "when the kill switch is off and the flag is not enabled" do
    let(:realtime_usage_enabled) { "false" }

    before do
      create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:))
      create(:subscription, customer:, plan:, organization:)
    end

    it "asks for both switches" do
      expect { invoke }.to output(/enable LAGO_REALTIME_USAGE_ENABLED and the realtime_usage flag/).to_stdout
    end
  end

  context "when an overridden plan repeats its parent's code" do
    let(:overridden_plan) { create(:plan, organization:, code: plan.code, parent: plan) }
    let(:billable_metric) { create(:max_billable_metric, organization:) }

    before do
      create(:standard_charge, plan:, billable_metric:)
      create(:standard_charge, plan: overridden_plan, billable_metric:)
      create(:subscription, customer:, plan:, organization:)
      create(:subscription, customer:, plan: overridden_plan, organization:)
    end

    it "counts the two charges apart, though they render as the same label" do
      expect { invoke }.to output(/unsupported_aggregation_type: 2 charge\(s\), 2 subscription\(s\)/).to_stdout
    end
  end

  context "when the charge carries a presentation breakdown" do
    before do
      create(
        :standard_charge,
        plan:,
        billable_metric: create(:sum_billable_metric, organization:),
        properties: {"amount" => "5", "presentation_group_keys" => [{"value" => "region"}]}
      )
      create(:subscription, customer:, plan:, organization:)
    end

    it "counts it as delegated, since ordinary current usage asks for the breakdown" do
      expect { invoke }.to output(/presentation_breakdown: 1 charge\(s\), 1 subscription\(s\)/).to_stdout
    end

    it "does not report it as servable" do
      expect { invoke }.to output(/Not worth enabling/).to_stdout
    end
  end
end
