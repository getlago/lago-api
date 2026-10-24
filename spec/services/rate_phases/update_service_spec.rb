# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::UpdateService do
  subject(:result) { described_class.call(rate_phase:, params:) }

  let_it_be(:organization) { create(:organization) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:launch) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, name: "Before", code: "launch") }
  let(:rate_phase) { launch }
  let(:terminal_position) { 2 }
  let!(:terminal) { create(:rate_phase, plan_rate_card:, organization:, position: terminal_position, billing_interval_cycle_count: nil, code: "forever") }
  let(:params) { {name: "After", billing_interval_cycle_count: 6} }

  before { create_default(:billable_metric) }

  def activity_payload(record, event_type)
    expect(kafka_messages.size).to eq(1)
    payload = JSON.parse(kafka_messages.first.fetch(:payload))
    expect(payload).to include(
      "activity_type" => event_type,
      "resource_id" => record.id,
      "resource_type" => record.class.name
    )
    payload
  end

  it "updates the phase" do
    expect(result).to be_success
    expect(rate_phase.reload.name).to eq("After")
    expect(rate_phase.billing_interval_cycle_count).to eq(6)
  end

  it "logs the phase update and publishes the owning plan_rate_card.updated webhook" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)

    expect(Utils::ActivityLog).to have_produced("rate_phase.updated").after_commit.with(rate_phase)
    expect(Utils::ActivityLog).not_to have_received(:produce).with(plan_rate_card, any_args)
  end

  it "locks the parent entry like the other sequence mutations" do
    allow(rate_phase).to receive(:plan_rate_card).and_return(plan_rate_card)
    allow(plan_rate_card).to receive(:with_lock).and_call_original

    result

    expect(plan_rate_card).to have_received(:with_lock)
  end

  context "when renaming the code" do
    let(:params) { {code: "intro"} }

    it "updates it" do
      expect(result).to be_success
      expect(rate_phase.reload.code).to eq("intro")
    end
  end

  context "when making a non-terminal phase indefinite" do
    let(:params) { {billing_interval_cycle_count: nil} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
    end

    context "when the cycle count is an empty string" do
      let(:params) { {billing_interval_cycle_count: ""} }

      it "treats it as indefinite and rejects it too" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
      end
    end
  end

  describe "rate override lifecycle" do
    let(:params) { {rate_override: {rate_model: "standard", rate_properties: {"amount" => "2"}}} }

    let!(:previous_override) { create(:rate_override, organization:) }

    before { rate_phase.update!(rate_override_id: previous_override.id) }

    it "replaces the override and discards the superseded one" do
      expect(result).to be_success
      expect(rate_phase.reload.rate_override.rate_properties).to eq({"amount" => "2"})
      expect(previous_override.reload).to be_discarded
    end

    context "when the override is null" do
      let(:params) { {rate_override: nil} }

      it "clears the override and discards it" do
        expect(result).to be_success
        expect(rate_phase.reload.rate_override).to be_nil
        expect(previous_override.reload).to be_discarded
      end
    end

    context "when the override is an empty object" do
      let(:params) { {rate_override: {}} }

      it "fails validation instead of clearing the override" do
        expect(result).not_to be_success
        expect(result.error.messages).to have_key(:rate_model)
        expect(rate_phase.reload.rate_override).to eq(previous_override)
        expect(previous_override.reload).not_to be_discarded
      end
    end

    context "when the phase save fails" do
      let(:params) { {code: "forever", rate_override: {rate_model: "standard", rate_properties: {"amount" => "2"}}} }

      it "rolls everything back without leaking an override" do
        expect { result }.not_to change(RateOverride, :count)

        expect(result).not_to be_success
        expect(previous_override.reload).not_to be_discarded
        expect(rate_phase.reload.rate_override).to eq(previous_override)
      end
    end
  end

  context "when making the last phase finite" do
    let(:rate_phase) { terminal }
    let(:params) { {billing_interval_cycle_count: 4} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_interval_cycle_count]).to eq(["last_phase_must_be_indefinite"])
      expect(terminal.reload.billing_interval_cycle_count).to be_nil
    end
  end

  describe "moving a phase" do
    let(:terminal_position) { 3 }
    let!(:ramp) { create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: 6, code: "ramp") }

    def positions
      plan_rate_card.rate_phases.order(:position).pluck(:code)
    end

    context "when moving a phase later" do
      let(:params) { {position: 2} }

      it "shifts the phases it passes up" do
        expect(result).to be_success
        expect(positions).to eq(%w[ramp launch forever])
      end
    end

    context "when moving a phase earlier" do
      let(:rate_phase) { ramp }
      let(:params) { {position: 1, name: "Ramp"} }

      it "shifts the phases it passes down and applies the other changes" do
        expect(result).to be_success
        expect(positions).to eq(%w[ramp launch forever])
        expect(ramp.reload.name).to eq("Ramp")
      end
    end

    context "when the position does not change" do
      let(:params) { {position: 1} }

      it "publishes the successful operation even though the serialized state is unchanged" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)
        expect(result).to be_success
        expect(positions).to eq(%w[launch ramp forever])
        expect(Utils::ActivityLog).to have_produced("rate_phase.updated").after_commit.with(rate_phase)
      end
    end

    context "when taking the last slot" do
      let(:params) { {position: 3} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:position]).to eq(["last_phase_must_be_indefinite"])
        expect(positions).to eq(%w[launch ramp forever])
      end
    end

    context "when moving the indefinite tail" do
      let(:rate_phase) { terminal }
      let(:params) { {position: 1} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:position]).to eq(["indefinite_phase_must_be_last"])
        expect(positions).to eq(%w[launch ramp forever])
      end
    end

    context "when several phases sit between the old and new slots" do
      let(:terminal_position) { 5 }

      before do
        create(:rate_phase, plan_rate_card:, organization:, position: 3, billing_interval_cycle_count: 2, code: "third")
        create(:rate_phase, plan_rate_card:, organization:, position: 4, billing_interval_cycle_count: 2, code: "fourth")
      end

      context "when moving later" do
        let(:params) { {position: 4} }

        it "shifts every passed phase up" do
          expect(result).to be_success
          expect(positions).to eq(%w[ramp third fourth launch forever])
          expect(plan_rate_card.rate_phases.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5])
        end
      end

      context "when moving earlier" do
        let(:rate_phase) { plan_rate_card.rate_phases.find_by(code: "fourth") }
        let(:params) { {position: 1} }

        it "shifts every passed phase down" do
          expect(result).to be_success
          expect(positions).to eq(%w[fourth launch ramp third forever])
          expect(plan_rate_card.rate_phases.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5])
        end
      end
    end

    context "when the position is out of range" do
      let(:params) { {position: 4} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:position]).to eq(["positions_must_be_contiguous"])
      end
    end

    context "when the position is null" do
      let(:params) { {position: nil} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:position]).to eq(["positions_must_be_contiguous"])
      end
    end

    context "when the position is not an integer" do
      [true, "2.9", "2garbage", 2.0].each do |value|
        context "with #{value.inspect}" do
          let(:params) { {position: value} }

          it "returns a validation failure without moving anything" do
            expect(result).not_to be_success
            expect(result.error.messages[:position]).to eq(["positions_must_be_contiguous"])
            expect(positions).to eq(%w[launch ramp forever])
          end
        end
      end
    end

    context "when the position is an integer string" do
      let(:params) { {position: "2"} }

      it "moves the phase" do
        expect(result).to be_success
        expect(positions).to eq(%w[ramp launch forever])
      end
    end

    context "when the position is blank" do
      let(:params) { {position: ""} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:position]).to eq(["positions_must_be_contiguous"])
      end
    end
  end

  context "when the plan has contracts" do
    before { create(:contract, catalog_plan: plan_rate_card.catalog_plan, organization: plan_rate_card.organization) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["plan_locked"])
    end
  end

  context "when the phase was deleted concurrently" do
    before { launch.discard! }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when rate_phase is nil" do
    let(:rate_phase) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the phase belongs to a contract rate card" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_phase) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1, billing_interval_cycle_count: nil)
    end
    let(:params) { {name: "Contract phase"} }

    it "logs the phase update and publishes the contract_rate_card.updated webhook" do
      rate_phase
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract_rate_card.updated", contract_rate_card)

      expect(Utils::ActivityLog).to have_produced("rate_phase.updated").after_commit.with(rate_phase)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(contract_rate_card, any_args)
    end
  end

  context "when logging phase changes", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:terminal_position) { 3 }
    let(:params) { {position: 2, code: "intro-v2", name: "New intro", billing_interval_cycle_count: 4} }

    before do
      create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: 6, code: "ramp")
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "logs the changed fields of the phase only" do
      expect(result).to be_success
      payload = activity_payload(launch, "rate_phase.updated")
      expect(payload.fetch("activity_object_changes")).to eq(
        "code" => ["launch", "intro-v2"],
        "name" => ["Before", "New intro"],
        "position" => [1, 2],
        "billing_interval_cycle_count" => [3, 4]
      )
    end
  end

  context "when an update leaves the phase unchanged", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:params) { {name: "Before"} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "still logs the update with an empty diff" do
      expect(result).to be_success
      expect(activity_payload(rate_phase, "rate_phase.updated").fetch("activity_object_changes")).to eq({})
    end
  end

  context "when an update is rejected", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:params) { {position: 99} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "does not log anything" do
      expect(result).not_to be_success
      expect(kafka_messages).to be_empty
    end
  end

  context "when logging a contract phase update", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_phase) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "forever", name: "Forever", position: 1, billing_interval_cycle_count: nil)
    end
    let(:params) { {name: "Contract forever"} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "logs the phase diff with the contract customer" do
      expect(result).to be_success
      payload = activity_payload(rate_phase, "rate_phase.updated")
      expect(payload).to include("external_customer_id" => customer.external_id)
      expect(payload.fetch("activity_object_changes")).to eq("name" => ["Forever", "Contract forever"])
    end
  end

  context "when the override is omitted", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:previous_override) { create(:rate_override, organization:, rate_model: "standard", rate_properties: {amount: "2"}) }
    let!(:launch) do
      create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, code: "launch", rate_override: previous_override)
    end
    let(:params) { {name: "Still here"} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "keeps the override out of the diff" do
      expect(result).to be_success
      payload = activity_payload(launch, "rate_phase.updated")
      expect(payload.fetch("activity_object_changes")).to eq("name" => [nil, "Still here"])
      expect(payload.fetch("activity_object").fetch("rate_override"))
        .to include("lago_id" => previous_override.id, "rate_properties" => {"amount" => "2"})
    end
  end

  context "when the override is cleared", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:previous_override) { create(:rate_override, organization:, rate_model: "standard", rate_properties: {amount: "2"}) }
    let!(:launch) do
      create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, code: "launch", rate_override: previous_override)
    end
    let(:params) { {rate_override: nil} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "includes the previous override ID and a null after value" do
      expect(result).to be_success
      old_value, new_value = activity_payload(launch, "rate_phase.updated").fetch("activity_object_changes").fetch("rate_override")
      expect(old_value).to include("lago_id" => previous_override.id)
      expect(new_value).to be_nil
    end
  end

  context "when override pricing changes", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:previous_override) { create(:rate_override, organization:, rate_model: "standard", rate_properties: {amount: "2"}) }
    let!(:launch) do
      create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, code: "launch", rate_override: previous_override)
    end
    let(:params) { {rate_override: {rate_model: "standard", rate_properties: {amount: "5"}}} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "records both override IDs and their pricing values" do
      expect(result).to be_success
      old_value, new_value = activity_payload(launch, "rate_phase.updated").fetch("activity_object_changes").fetch("rate_override")
      expect(old_value).to include("lago_id" => previous_override.id, "rate_properties" => {"amount" => "2"})
      expect(new_value).to include("rate_properties" => {"amount" => "5"})
      expect(new_value.fetch("lago_id")).not_to eq(previous_override.id)
    end
  end

  context "when override pricing is equal but the ID changes", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let(:previous_override) { create(:rate_override, organization:, rate_model: "standard", rate_properties: {amount: "5"}) }
    let!(:launch) do
      create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, code: "launch", rate_override: previous_override)
    end
    let(:params) { {rate_override: {rate_model: "standard", rate_properties: {amount: "5"}}} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "retains the equal pricing values and exposes the replacement ID" do
      expect(result).to be_success
      old_value, new_value = activity_payload(launch, "rate_phase.updated").fetch("activity_object_changes").fetch("rate_override")
      expect(old_value).to include("rate_properties" => {"amount" => "5"})
      expect(new_value).to include("rate_properties" => {"amount" => "5"})
      expect(new_value.fetch("lago_id")).not_to eq(old_value.fetch("lago_id"))
    end
  end
end
