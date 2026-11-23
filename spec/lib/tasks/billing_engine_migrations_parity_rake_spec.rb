# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:parity" do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let_it_be(:shadow_customer) do
    create(:customer, organization: shadow_organization, external_id: customer.external_id, timezone: "UTC", currency: "EUR")
  end
  let_it_be(:billable_metric) { create(:billable_metric, organization:, code: "api_calls", aggregation_type: :count_agg) }
  let_it_be(:plan) { create(:plan, organization:, interval: "monthly", amount_currency: "EUR") }
  let_it_be(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "2"}) }
  let_it_be(:shadow_billable_metric) do
    create(:billable_metric, organization: shadow_organization, code: "api_calls", aggregation_type: :count_agg)
  end
  let_it_be(:product) { create(:product, organization: shadow_organization, billable_metric: shadow_billable_metric) }
  let_it_be(:rate_card) { create(:rate_card, organization: shadow_organization, product:, currency: "EUR") }
  let_it_be(:rate) do
    create(:rate_card_rate, organization: shadow_organization, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})
  end

  let(:task) { Rake::Task["billing_engine_migrations:parity"] }
  let(:env) { {} }
  let(:status) { "shadowing" }
  let(:migration) do
    create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping: {plan.code => "catalog_plan"})
  end

  let(:started_at) { Time.zone.parse("2027-01-01") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:, subscription_at: started_at) }
  let(:contract) { create_shadow_contract(external_id: subscription.external_id, code: subscription.id) }

  def create_shadow_contract(*traits, external_id:, code:, **attributes)
    create(:contract, *traits, organization: shadow_organization, customer: shadow_customer, external_id:, code:,
      started_at:, **attributes)
  end

  def send_event(event_organization, external_subscription_id)
    create(:event, organization_id: event_organization.id, external_subscription_id:, code: "api_calls",
      timestamp: Time.zone.parse("2027-02-05"))
  end

  around { |example| travel_to(Time.zone.parse("2027-02-10 12:00:00")) { example.run } }

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable
    stub_const("ENV", ENV.to_h.merge(env))

    migration
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

  context "when the migration is aborted" do
    let(:status) { "aborted" }

    it "aborts" do
      expect { task.invoke(organization.id) }.to raise_error(SystemExit).and output(/is aborted/).to_stderr
    end
  end

  context "when LIMIT is not a positive integer" do
    let(:env) { {"LIMIT" => "0"} }

    it "aborts" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit).and output(/LIMIT must be a positive integer/).to_stderr
    end
  end

  context "when AFTER is not a contract of the shadow organization" do
    let(:env) { {"AFTER" => create(:contract).id} }

    it "aborts" do
      expect { task.invoke(organization.id) }
        .to raise_error(SystemExit).and output(/AFTER must be the id of a contract of shadow organization/).to_stderr
    end
  end

  context "with a copied subscription" do
    before do
      create(:contract_rate_card, organization: shadow_organization, contract:, rate_card:,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
      send_event(organization, subscription.external_id)
      send_event(shadow_organization, contract.external_id)
    end

    context "when the usage matches" do
      it "reports no mismatch" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including("Contracts compared: 1, matching: 1, mismatches: 0, skipped: 0, errors: 0")
        ).to_stdout
      end
    end

    context "when the migration is paused" do
      let(:status) { "paused" }

      it "still compares the contracts" do
        expect { task.invoke(organization.id) }.to output(a_string_including("Contracts compared: 1, matching: 1")).to_stdout
      end
    end

    context "when an event reached V1 only" do
      before { send_event(organization, subscription.external_id) }

      it "reports the contract and the metric with both amounts" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            # V1: 2 events at 2 EUR, V2: 1 event at 2 EUR
            "mismatch on contract #{contract.external_id} (subscription #{subscription.id}), " \
            "metric api_calls: V1 400 cents / 2.0 units, V2 200 cents / 1.0 units",
            "Contracts compared: 1, matching: 0, mismatches: 1, skipped: 0, errors: 0"
          )
        ).to_stdout
      end
    end

    context "when an event reached the shadow organization only" do
      before { send_event(shadow_organization, contract.external_id) }

      it "reports the contract and the metric with both amounts" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including("metric api_calls: V1 200 cents / 1.0 units, V2 400 cents / 2.0 units", "mismatches: 1")
        ).to_stdout
      end
    end

    context "when a usage cannot be computed" do
      before do
        allow(Contracts::CurrentUsageService).to receive(:call).and_return(
          Contracts::CurrentUsageService::Result.new.service_failure!(code: "usage_unavailable", message: "store timeout")
        )
      end

      it "reports the error and goes on" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            "error on contract #{contract.external_id}: usage_unavailable: store timeout",
            "Contracts compared: 0, matching: 0, mismatches: 0, skipped: 0, errors: 1"
          )
        ).to_stdout
      end
    end

    context "when a usage computation raises" do
      before do
        allow(Invoices::CustomerUsageService).to receive(:call!)
          .and_raise(ActiveRecord::QueryCanceled, "canceling statement due to statement timeout")
      end

      it "reports the error and goes on" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            "error on contract #{contract.external_id}: ActiveRecord::QueryCanceled: " \
            "canceling statement due to statement timeout",
            "Contracts compared: 0, matching: 0, mismatches: 0, skipped: 0, errors: 1"
          )
        ).to_stdout
      end
    end
  end

  context "with contracts out of sync with their V1 subscription" do
    let(:orphan_contract) { create_shadow_contract(external_id: "orphan", code: "not-a-subscription") }
    let(:terminated_subscription) { create(:subscription, :terminated, organization:, customer:, plan:) }
    let(:terminated_subscription_contract) do
      create_shadow_contract(external_id: terminated_subscription.external_id, code: terminated_subscription.id)
    end
    let(:ending_subscription) { create(:subscription, organization:, customer:, plan:, ending_at: 1.month.from_now) }
    let(:ending_subscription_contract) do
      create_shadow_contract(external_id: ending_subscription.external_id, code: ending_subscription.id)
    end
    let(:other_organization_subscription) { create(:subscription) }
    let(:other_organization_contract) do
      create_shadow_contract(external_id: other_organization_subscription.external_id, code: other_organization_subscription.id)
    end

    before do
      orphan_contract
      terminated_subscription_contract
      ending_subscription_contract
      other_organization_contract
      create_shadow_contract(:terminated, external_id: "ended", code: subscription.id)
    end

    it "skips them with the reason and leaves out the contracts that are not active" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "skipped contract #{orphan_contract.external_id} (subscription_not_found)",
          "skipped contract #{other_organization_contract.external_id} (subscription_not_found)",
          "skipped contract #{terminated_subscription_contract.external_id} (subscription_no_longer_active)",
          "skipped contract #{ending_subscription_contract.external_id} (ending_at_changed)",
          "Contracts compared: 0, matching: 0, mismatches: 0, " \
          "skipped: 4 (ending_at_changed: 1, subscription_no_longer_active: 1, subscription_not_found: 2), errors: 0"
        )
      ).to_stdout
    end
  end

  context "with more contracts than LIMIT" do
    let(:env) { {"LIMIT" => "1"} }
    let(:older_contract) { create_shadow_contract(external_id: "older", code: "older", created_at: 2.hours.ago) }
    let(:newer_contract) { create_shadow_contract(external_id: "newer", code: "newer", created_at: 1.hour.ago) }

    before do
      older_contract
      newer_contract
    end

    it "examines the newest contracts first and says how to continue" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "skipped contract newer (subscription_not_found)",
          "skipped: 1 (subscription_not_found: 1)",
          "Stopped at 1 contract(s): continue with AFTER=#{newer_contract.id}"
        )
      ).to_stdout
    end

    context "with AFTER" do
      let(:env) { {"LIMIT" => "1", "AFTER" => newer_contract.id} }

      it "continues after that contract" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including("skipped contract older (subscription_not_found)", "skipped: 1 (subscription_not_found: 1)")
        ).to_stdout
      end

      it "does not offer to continue after the last contract" do
        expect { task.invoke(organization.id) }.not_to output(/continue with AFTER/).to_stdout
      end
    end
  end

  context "with exactly LIMIT contracts" do
    let(:env) { {"LIMIT" => "2"} }

    before do
      create_shadow_contract(external_id: "first", code: "first")
      create_shadow_contract(external_id: "second", code: "second")
    end

    it "examines them all" do
      expect { task.invoke(organization.id) }.to output(a_string_including("skipped: 2 (subscription_not_found: 2)")).to_stdout
    end

    it "does not offer to continue" do
      expect { task.invoke(organization.id) }.not_to output(/continue with AFTER/).to_stdout
    end
  end
end
