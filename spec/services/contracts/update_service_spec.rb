# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::UpdateService do
  subject(:result) { described_class.call(contract:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:params) { {name: "Renamed", billing_anchor_date: "2026-03-01"} }
  let(:activity_log_results) { [] }

  before do
    # Updated activity logging wraps the service call and must return its result.
    allow(Utils::ActivityLog).to receive(:produce) do |&block|
      activity_log_results << block.call
      activity_log_results.last
    end
    allow(Utils::ActivityLog).to receive(:produce_after_commit)
  end

  it "updates the editable authoring fields" do
    expect(result).to be_success
    expect(contract.reload).to have_attributes(name: "Renamed", billing_anchor_date: Date.new(2026, 3, 1))
  end

  context "when the billing schedule is locked" do
    before { allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

    it "returns a concurrency failure without changing the contract" do
      expect { result }.not_to change { contract.reload.attributes }
      expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
    end
  end

  it "publishes contract.updated after a successful update" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.updated", contract)

    expect(Utils::ActivityLog).to have_received(:produce).with(
      contract,
      "contract.updated",
      after_commit: true
    )
  end

  ["draft", "active", nil].each do |status|
    context "with a #{status.inspect} status on a pending contract" do
      let(:params) { {name: "Renamed", status:} }

      it "refuses it without changing the contract or notifying" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result.error.messages).to eq(status: ["value_is_invalid"])
        expect(contract.reload.name).not_to eq("Renamed")
      end
    end
  end

  context "with the current status, as a client resends the contract it read" do
    let(:params) { {name: "Renamed", status: "pending"} }

    it "updates the contract" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(name: "Renamed", status: "pending")
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
      let(:params) { {name: "Renamed", status: "active"} }

      it "does not treat the status as a locked field" do
        expect(result).to be_success
        expect(contract.reload.name).to eq("Renamed")
      end
    end
  end

  context "when no serialized fields change" do
    let(:params) { {} }

    it "publishes contract.updated after a no-op update" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.updated", contract)
      expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract.updated", after_commit: true)
    end
  end

  it "sets the window dates in the customer timezone" do
    result = described_class.call(contract:, params: {started_at: "2026-11-01T00:00:00", ended_at: "2026-12-01T00:00:00"})

    expect(result).to be_success
    expect(contract.reload.started_at).to eq(Time.zone.parse("2026-11-01T00:00:00"))
    expect(contract.ended_at).to eq(Time.zone.parse("2026-12-01T00:00:00"))
  end

  context "when the contract is active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:params) do
      {
        name: "Renamed",
        purchase_order_number: "PO-42",
        ended_at: "2027-01-01T00:00:00Z",
        billing_entity_id: billing_entity.id,
        consolidate_invoice: false,
        payment_method: {payment_method_type: "manual"}
      }
    end

    around { |example| travel_to(Time.zone.parse("2026-10-01T00:00:00Z")) { example.run } }

    it "updates the fields that stay editable" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(
        name: "Renamed",
        purchase_order_number: "PO-42",
        billing_entity:,
        consolidate_invoice: false
      )
      expect(contract).to be_payment_method_type_manual
      expect(contract.ended_at).to eq(Time.zone.parse("2027-01-01T00:00:00Z"))
    end

    context "when the form resends the locked fields unchanged" do
      let(:started_at) { Time.zone.parse("2026-09-01T03:30:00.123456Z") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
      let(:params) do
        {
          name: "Renamed",
          plan_code: catalog_plan.code,
          started_at: "2026-09-01T03:30:00Z",
          billing_anchor_date: contract.effective_billing_anchor_date.iso8601
        }
      end

      it "accepts the edit without writing the locked fields back" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(name: "Renamed", started_at:, billing_anchor_date: nil)
      end
    end

    context "without a plan" do
      let(:catalog_plan) { nil }

      [nil, ""].each do |plan_code|
        context "with #{plan_code.inspect} as the plan code" do
          let(:params) { {name: "Renamed", plan_code:} }

          it "accepts the edit" do
            expect(result).to be_success
            expect(contract.reload.name).to eq("Renamed")
          end
        end
      end
    end

    context "when the form resends the code of the plan it has since discarded" do
      let(:params) { {name: "Renamed", plan_code: catalog_plan.code} }

      before { catalog_plan.discard! }

      it "accepts the edit" do
        expect(result).to be_success
        expect(contract.reload.name).to eq("Renamed")
      end
    end

    describe "end date" do
      let(:ended_at) { Time.zone.parse("2027-01-01T00:00:00Z") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, ended_at:) }

      context "when bringing it forward" do
        let(:params) { {ended_at: "2026-12-01T00:00:00Z"} }

        it "updates it" do
          expect(result).to be_success
          expect(contract.reload.ended_at).to eq(Time.zone.parse("2026-12-01T00:00:00Z"))
        end
      end

      context "when resending it unchanged" do
        let(:params) { {name: "Renamed", ended_at: "2027-01-01T00:00:00Z"} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end

      context "when resending one that has already passed" do
        let(:ended_at) { Time.zone.parse("2026-09-30T00:00:00Z") }
        let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-09-01T00:00:00Z"), ended_at:) }
        let(:params) { {name: "Renamed", ended_at: "2026-09-30T00:00:00Z"} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end

      context "when setting one that has already passed" do
        let(:params) { {ended_at: "2026-09-15T00:00:00Z"} }

        it "rejects it" do
          expect(result).not_to be_success
          expect(result.error.messages[:ended_at]).to eq(["already_ended"])
          expect(contract.reload.ended_at).to eq(ended_at)
        end
      end

      context "when moving it later" do
        let(:params) { {ended_at: "2027-02-01T00:00:00Z"} }

        it "updates it" do
          expect(result).to be_success
          expect(contract.reload.ended_at).to eq(Time.zone.parse("2027-02-01T00:00:00Z"))
        end
      end

      context "when clearing it" do
        let(:params) { {ended_at: nil} }

        it "clears it" do
          expect(result).to be_success
          expect(contract.reload.ended_at).to be_nil
        end
      end
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:params) { {name: "Renamed", plan_code: other_plan.code} }

      it "rejects the edit as locked and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages[:contract]).to eq(["contract_locked"])
        expect(contract.reload).to have_attributes(name: nil, catalog_plan:)
      end
    end

    {
      billing_anchor_date: "2026-03-01",
      started_at: "2026-03-01T00:00:00Z"
    }.each do |field, value|
      context "when changing #{field}" do
        let(:params) { {name: "Renamed"}.merge(field => value) }

        it "rejects the edit as locked and changes nothing" do
          expect(result).not_to be_success
          expect(result.error.messages[:contract]).to eq(["contract_locked"])
          expect(contract.reload.name).to be_nil
        end
      end
    end
  end

  %i[terminated canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }
      let(:params) { {name: "Renamed"} }

      it "rejects any edit as locked" do
        expect(result).not_to be_success
        expect(result.error.messages[:contract]).to eq(["contract_locked"])
        expect(contract.reload.name).to be_nil
      end
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "with invoice custom sections" do
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:params) { {invoice_custom_section: {invoice_custom_section_ids: [section.id]}} }

    it "attaches the sections to the contract" do
      expect(result).to be_success
      expect(contract.reload.selected_invoice_custom_sections).to eq([section])
    end
  end

  context "when changing the invoice custom sections of an active contract" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:params) { {invoice_custom_section: {invoice_custom_section_ids: [section.id]}} }

    it "attaches them, as an administrative field" do
      expect(result).to be_success
      expect(contract.reload.selected_invoice_custom_sections).to eq([section])
    end
  end

  context "when an active contract sends sections with a locked field" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:params) { {billing_anchor_date: "2026-03-01", invoice_custom_section: {invoice_custom_section_ids: [section.id]}} }

    it "rejects the edit and attaches nothing" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract.reload.selected_invoice_custom_sections).to be_empty
    end
  end

  context "when a terminated contract sends sections" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:params) { {invoice_custom_section: {invoice_custom_section_ids: [section.id]}} }

    it "rejects the edit" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract.reload.selected_invoice_custom_sections).to be_empty
    end
  end

  context "when skipping invoice custom sections" do
    let(:params) { {invoice_custom_section: {skip_invoice_custom_sections: true}} }

    before { create(:contract_applied_invoice_custom_section, organization:, contract:) }

    it "flags the contract and removes the attached sections" do
      expect(result).to be_success
      expect(contract.reload.skip_invoice_custom_sections).to be(true)
      expect(contract.applied_invoice_custom_sections).to be_empty
    end
  end

  context "when changing the plan" do
    let(:new_rate_card) { create(:rate_card, organization:) }
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:params) { {plan_code: other_plan.code} }
    let(:old_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:)) }
    let(:old_phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card: old_card) }

    let(:new_plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: new_rate_card, units: 3) }

    before do
      old_phase
      create(:rate_phase, organization:, plan_rate_card: new_plan_rate_card, code: "intro", position: 1)
    end

    it "re-materializes the rate cards from the new plan with their phases" do
      expect(result).to be_success
      expect(contract.reload.catalog_plan).to eq(other_plan)
      card = contract.applied_rate_cards.sole
      expect(card.rate_card).to eq(new_rate_card)
      expect(card.terms.sole.units).to eq(3)
      expect(card.rate_phases.map(&:code)).to eq(["intro"])
    end

    it "discards the replaced cards along with their phases" do
      result

      expect(old_card.reload).to be_discarded
      expect(old_phase.reload).to be_discarded
    end

    it "publishes one contract.updated pair with the old and new card hierarchy" do
      old_card
      old_phase
      new_plan_rate_card
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).exactly(1).times

      expect(SendWebhookJob).to have_been_enqueued.with("contract.updated", contract)
      expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract.updated", after_commit: true)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "contract_rate_card.deleted", any_args)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "contract_rate_card.created", any_args)
    end

    context "when the contract has a wallet from its previous plan" do
      let(:old_wallet) { create(:catalog_wallet, organization:, contract:, customer:, code: "ai_credits") }
      let(:old_allocation) { create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: old_wallet) }
      let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan: other_plan, code: "ai_credits") }

      before do
        old_allocation
        create(:plan_wallet_credit_allocation, organization:, plan_wallet:, code: "monthly_allowance")
      end

      it "discards the wallet along with its rules" do
        expect(result).to be_success

        expect(old_wallet.reload).to be_discarded
        expect(old_allocation.reload).to be_discarded
      end

      it "gives the contract no wallet from the new plan" do
        expect(result).to be_success

        expect(contract.reload.wallets).to be_empty
      end

      context "when the contract has a second wallet" do
        let(:second_wallet) { create(:catalog_wallet, organization:, contract:, customer:, code: "support_credits") }

        before { second_wallet }

        it "discards each of them" do
          expect(result).to be_success

          expect([old_wallet, second_wallet].map(&:reload)).to all(be_discarded)
        end
      end

      context "when another contract of the customer has a wallet" do
        let(:other_wallet) { create(:catalog_wallet, organization:, customer:, code: "ai_credits") }

        before { other_wallet }

        it "keeps that wallet" do
          expect(result).to be_success

          expect(other_wallet.reload).not_to be_discarded
        end
      end

      context "when the organization has contract wallets enabled" do
        let(:organization) { create(:organization, feature_flags: %w[product_catalog catalog_wallets]) }

        it "gives the contract the new plan's wallet only" do
          expect(result).to be_success

          wallet = contract.reload.wallets.sole
          expect(wallet).not_to eq(old_wallet)
          expect(wallet).to have_attributes(code: "ai_credits", customer:)
          expect(wallet.credit_allocations.sole.code).to eq("monthly_allowance")
        end
      end

      context "when the wallets have alerts" do
        let(:old_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: old_wallet, code: "low_balance", name: "Edited on the contract") }
        let(:old_threshold) { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: old_alert, value: 100) }
        let(:alert_template) { create(:plan_wallet_alert, organization:, plan_wallet:, code: "low_balance", name: "Low balance") }

        before do
          old_threshold
          create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: alert_template, value: 2_000)
        end

        it "deletes the alerts of the discarded wallet, thresholds included" do
          expect(result).to be_success

          expect(UsageMonitoring::CatalogWalletAlert.where(id: old_alert.id)).to be_empty
          expect(UsageMonitoring::CatalogWalletAlertThreshold.where(id: old_threshold.id)).to be_empty
        end

        context "when another contract of the customer has a wallet with alerts" do
          let(:other_wallet) { create(:catalog_wallet, organization:, customer:, code: "ai_credits") }
          let(:other_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: other_wallet, code: "low_balance") }
          let(:other_threshold) { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: other_alert, value: 100) }

          before { other_threshold }

          it "keeps that wallet's alerts" do
            expect(result).to be_success

            expect(other_alert.reload.thresholds).to eq([other_threshold])
          end
        end

        context "when the organization has contract wallets enabled" do
          let(:organization) { create(:organization, feature_flags: %w[product_catalog catalog_wallets]) }

          it "gives the new wallet the new plan's alerts, not the edits made on the old one" do
            expect(result).to be_success

            alert = contract.reload.wallets.sole.alerts.sole
            expect(alert).to have_attributes(code: "low_balance", name: "Low balance")
            expect(alert.thresholds.pluck(:value)).to eq([2_000])
          end
        end
      end
    end

    context "when the plan is removed" do
      let(:params) { {plan_code: nil} }
      let(:wallet) { create(:catalog_wallet, organization:, contract:, customer:) }

      before { wallet }

      it "discards the contract's wallets" do
        expect(result).to be_success

        expect(contract.reload.catalog_plan).to be_nil
        expect(wallet.reload).to be_discarded
      end
    end
  end

  context "when moving the start of a pending contract" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-15")) }
    let(:activation_product) { create(:product, :fixed, organization:) }
    let(:activation_rate_card) { create(:rate_card, organization:, product: activation_product, billing_timing: "advance") }
    let(:inherited_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card: activation_rate_card,
        effective_date: Date.new(2026, 10, 15),
        billing_anchor_date: Date.new(2026, 10, 15)
      )
    end
    let(:anchored_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        effective_date: Date.new(2026, 10, 15),
        billing_anchor_date: Date.new(2026, 10, 1)
      )
    end
    let(:params) { {started_at: "2026-11-01T00:00:00"} }

    around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

    before do
      inherited_card
      anchored_card
      create(:rate_card_rate, organization:, rate_card: activation_rate_card, effective_from: Time.zone.parse("2026-09-01"), billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "starts its cards on the new date, keeping an anchor set on a card" do
      expect(result).to be_success
      expect(contract.reload).to be_pending
      expect(inherited_card.reload).to have_attributes(
        effective_date: Date.new(2026, 11, 1),
        billing_anchor_date: Date.new(2026, 11, 1)
      )
      expect(anchored_card.reload).to have_attributes(effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 10, 1))
    end

    context "with a card left on a start date moved before cards followed it" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-20")) }
      let(:stale_card) do
        create(
          :contract_rate_card,
          organization:,
          contract:,
          effective_date: Date.new(2026, 10, 15),
          billing_anchor_date: Date.new(2026, 10, 15)
        )
      end
      let(:params) { {started_at: "2026-11-01T00:00:00"} }

      before { stale_card }

      it "treats its anchor on the old start day as inherited" do
        result

        expect(stale_card.reload).to have_attributes(effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
      end
    end

    context "with an anchor set on a card to the start day of a contract with its own anchor" do
      let(:contract) do
        create(:contract, :pending, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-15"), billing_anchor_date: Date.new(2026, 10, 1))
      end
      let(:own_anchor_card) do
        create(
          :contract_rate_card,
          organization:,
          contract:,
          effective_date: Date.new(2026, 10, 15),
          billing_anchor_date: Date.new(2026, 10, 15)
        )
      end

      before { own_anchor_card }

      it "keeps the card's anchor" do
        result

        expect(own_anchor_card.reload).to have_attributes(effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 10, 15))
      end
    end

    context "when the anchor moves along with the invoice section settings" do
      let(:params) { {billing_anchor_date: "2026-10-20", invoice_custom_section: {skip_invoice_custom_sections: true}} }

      it "still moves the inherited card anchors" do
        result

        expect(inherited_card.reload.billing_anchor_date).to eq(Date.new(2026, 10, 20))
      end
    end

    context "when only the anchor moves" do
      let(:params) { {billing_anchor_date: "2026-10-20"} }

      it "moves the inherited card anchors only" do
        expect(result).to be_success
        expect(inherited_card.reload.billing_anchor_date).to eq(Date.new(2026, 10, 20))
        expect(anchored_card.reload.billing_anchor_date).to eq(Date.new(2026, 10, 1))
      end
    end

    context "when the clock activated the contract since it was loaded" do
      before { Contract.where(id: contract.id).update_all(status: :active) } # rubocop:disable Rails/SkipsModelValidations

      it "applies the active rules and leaves the start in place" do
        expect(result.error.messages[:contract]).to eq(["contract_locked"])
        expect(contract.reload.started_at).to eq(Time.zone.parse("2026-10-15"))
        expect(inherited_card.reload.effective_date).to eq(Date.new(2026, 10, 15))
      end
    end

    context "when the new start has arrived" do
      let(:params) { {started_at: "2026-09-29T00:00:00"} }

      it "activates the contract and schedules its billing" do
        expect(result).to be_success
        expect(contract.reload).to be_active
        expect(inherited_card.reload.effective_date).to eq(Date.new(2026, 9, 29))
        expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id)
        expect(inherited_card.reload.next_billing_at).to eq(Time.zone.parse("2026-09-29"))
        expect(inherited_card.billing_operations.sole).to have_attributes(
          action_type: "renew_fixed_advance", reason: "contract_activation",
          billing_at: Time.zone.parse("2026-09-29"), target_cycle_started_at: Time.zone.parse("2026-09-29")
        )
        expect(LegacyBillingSegment.where(contract_rate_card_id: inherited_card.id)).to be_empty
      end

      context "when cursor persistence fails" do
        let(:failure_product) { create(:product, :fixed, organization:) }
        let(:failure_rate_card) { create(:rate_card, organization:, product: failure_product, billing_timing: "advance") }
        let(:failure_card) do
          create(
            :contract_rate_card, organization:, contract:,
            rate_card: failure_rate_card,
            effective_date: Date.new(2026, 9, 29), billing_anchor_date: Date.new(2026, 9, 29)
          )
        end
        let(:operation_writes) { [] }

        before do
          failure_card
          create(:rate_card_rate, organization:, rate_card: failure_card.rate_card, effective_from: Time.zone.parse("2026-09-01"), billing_interval_count: 1, billing_interval_unit: "month")
          allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_wrap_original do |original, **attributes|
            operation_writes << attributes
            raise ActiveRecord::RecordInvalid.new(failure_card) if operation_writes.size == 2

            original.call(**attributes)
          end
        end

        it "rolls back the moved start, activation and earlier cursors" do
          expect { result }.not_to change { inherited_card.reload.next_billing_at }
          expect(result).not_to be_success
          expect(contract.reload).to have_attributes(status: "pending", started_at: Time.zone.parse("2026-10-15"))
          expect(BillingOperation.where(contract_rate_card_id: [inherited_card.id, failure_card.id])).to be_empty
        end
      end

      it "publishes contract.updated and exactly one contract.started pair" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).exactly(2).times

        expect(SendWebhookJob).to have_been_enqueued.with("contract.updated", contract)
        expect(SendWebhookJob).to have_been_enqueued.with("contract.started", contract)
        expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract.updated", after_commit: true)
        expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.started")
      end

      context "when an active contract shares its external id" do
        before { create(:contract, organization:, customer:, external_id: contract.external_id) }

        it "fails and keeps the previous start" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)
          expect(result.error.messages[:external_id]).to eq(["active_contract_exists"])
          expect(contract.reload).to have_attributes(status: "pending", started_at: Time.zone.parse("2026-10-15"))
          expect(inherited_card.reload.effective_date).to eq(Date.new(2026, 10, 15))
          expect(Utils::ActivityLog).to have_received(:produce).with(contract, "contract.updated", after_commit: true)
          expect(activity_log_results).to eq([result])
          expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.started", any_args)
        end
      end
    end
  end

  context "when the contract is a draft" do
    let(:contract) { create(:contract, :draft, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-15")) }

    around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:new_rate_card) { create(:rate_card, organization:) }
      let(:old_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:)) }
      let(:params) { {plan_code: other_plan.code} }

      before do
        old_card
        create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: new_rate_card)
      end

      it "re-materializes the rate cards from the new plan" do
        expect(result).to be_success
        expect(contract.reload.catalog_plan).to eq(other_plan)
        expect(contract.applied_rate_cards.map(&:rate_card)).to eq([new_rate_card])
        expect(old_card.reload).to be_discarded
      end
    end

    context "when moving the start into the past" do
      let(:params) { {started_at: "2026-09-01T00:00:00"} }

      it "applies the authoring fields and keeps it a draft" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(
          status: "draft", started_at: Time.zone.parse("2026-09-01")
        )
      end
    end
  end

  context "when renaming a pending contract whose start has passed" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, started_at: 1.hour.ago) }
    let(:params) { {name: "Renamed"} }

    before { create(:contract, organization:, customer:, external_id: contract.external_id) }

    it "leaves activation to the clock, so the edit goes through next to an active sibling" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(name: "Renamed", status: "pending")
    end
  end

  context "when resending the current plan code" do
    let(:params) { {name: "Renamed", plan_code: catalog_plan.code} }

    it "accepts the edit" do
      expect(result).to be_success
      expect(contract.reload.name).to eq("Renamed")
    end

    context "when the contract has a wallet" do
      let(:organization) { create(:organization, feature_flags: %w[product_catalog catalog_wallets]) }
      let(:wallet) { create(:catalog_wallet, organization:, contract:, customer:) }

      before do
        wallet
        create(:plan_wallet, organization:, catalog_plan:)
      end

      it "keeps the contract's wallets as they are" do
        expect(result).to be_success

        expect(contract.reload.wallets).to eq([wallet])
      end
    end
  end

  context "without a plan" do
    let(:catalog_plan) { nil }

    [nil, ""].each do |plan_code|
      context "with #{plan_code.inspect} as the plan code" do
        let(:params) { {name: "Renamed", plan_code:} }

        it "accepts the edit" do
          expect(result).to be_success
          expect(contract.reload.name).to eq("Renamed")
        end
      end
    end
  end

  context "when the plan code is unknown" do
    let(:params) { {plan_code: "unknown"} }

    it "returns a not found plan failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "with a malformed date" do
    let(:params) { {started_at: "not-a-date"} }

    it "rejects the value" do
      expect(result).not_to be_success
      expect(result.error.messages[:started_at]).to eq(["value_is_invalid"])
    end
  end

  context "with a boolean date value" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, ended_at: 1.month.from_now) }
    let(:params) { {ended_at: false} }

    it "rejects it instead of silently clearing the end date" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["value_is_invalid"])
      expect(contract.reload.ended_at).to be_present
    end
  end

  context "when clearing a date with an explicit null" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, ended_at: 1.month.from_now) }
    let(:params) { {ended_at: nil} }

    it "clears the end date" do
      expect(result).to be_success
      expect(contract.reload.ended_at).to be_nil
    end
  end

  context "when the end date is already in the past" do
    let(:params) { {ended_at: 1.day.ago.iso8601} }

    it "rejects the ended_at" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["already_ended"])
    end
  end

  context "with billing, invoicing and payment settings" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:payment_method) { create(:payment_method, customer:) }
    let(:params) do
      {
        billing_entity_id: billing_entity.id,
        consolidate_invoice: false,
        purchase_order_number: "PO-42",
        payment_method: {payment_method_id: payment_method.id, payment_method_type: "provider"}
      }
    end

    it "updates the settings" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(
        billing_entity:,
        consolidate_invoice: false,
        purchase_order_number: "PO-42",
        payment_method:,
        payment_method_type: "provider"
      )
    end

    context "when a manual type is paired with a concrete payment method" do
      let(:params) { {payment_method: {payment_method_id: payment_method.id, payment_method_type: "manual"}} }

      it "rejects the contradictory combination" do
        expect(result).not_to be_success
        expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
      end
    end

    context "when the billing entity id is unknown" do
      let(:params) { {billing_entity_id: "00000000-0000-0000-0000-000000000000"} }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("billing_entity")
      end
    end

    context "when the payment method belongs to another customer" do
      let(:other_payment_method) { create(:payment_method, customer: create(:customer, organization:)) }
      let(:params) { {payment_method: {payment_method_id: other_payment_method.id}} }

      it "returns a not found failure, scoped to the contract's customer" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("payment_method")
      end
    end

    context "when consolidate_invoice is omitted" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, consolidate_invoice: false) }
      let(:params) { {name: "Renamed"} }

      it "leaves the stored value unchanged" do
        expect(result).to be_success
        expect(contract.reload.consolidate_invoice).to be(false)
      end
    end

    context "when payment_method_type is omitted" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:, payment_method_type: "manual") }
      let(:params) { {name: "Renamed"} }

      it "leaves the stored payment_method_type unchanged" do
        expect(result).to be_success
        expect(contract.reload.payment_method_type).to eq("manual")
      end
    end

    context "when clearing the override fields with an explicit null" do
      let(:contract) do
        create(:contract, :pending, organization:, customer:, catalog_plan:,
          billing_entity:, purchase_order_number: "PO-1")
      end
      let(:params) { {billing_entity_id: nil, purchase_order_number: nil} }

      it "clears the billing entity override and the purchase order number" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(billing_entity: nil, purchase_order_number: nil)
      end
    end
  end
end
