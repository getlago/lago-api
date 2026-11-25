# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::TerminateRelationsService do
  subject(:terminate_service) { described_class.new(customer:) }

  before_all do
    create_default(:organization)
  end

  let_it_be(:customer) { create(:customer, :deleted) }

  context "with an active subscription" do
    let(:subscription) { create(:subscription, customer:) }

    before { subscription }

    it "terminates the subscription" do
      freeze_time do
        expect { terminate_service.call }
          .to change { subscription.reload.status }.from("active").to("terminated")
          .and change(subscription, :terminated_at).from(nil).to(Time.current)
      end
    end
  end

  context "with a pending subscription" do
    let(:subscription) { create(:subscription, :pending, customer:) }

    before { subscription }

    it "cancels the subscription" do
      freeze_time do
        expect { terminate_service.call }
          .to change { subscription.reload.status }.from("pending").to("canceled")
          .and change(subscription, :canceled_at).from(nil).to(Time.current)
      end
    end
  end

  context "with draft invoices" do
    let(:subscription) { create(:subscription, customer:) }

    let_it_be(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      create(:invoice_subscription, invoice: invoices.first, subscription:, invoicing_reason: :subscription_starting)
      create(:invoice_subscription, invoice: invoices.last, subscription:, invoicing_reason: :subscription_periodic)
    end

    it "enqueues finalize jobs for the invoices" do
      expect do
        terminate_service.call
      end.to have_enqueued_job(Invoices::FinalizeJob).exactly(:twice)
    end
  end

  context "with draft invoices and a live contract on the shadow organization of a migration" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)
      contract
      invoices
    end

    it "cancels the contract and deletes the drafts instead of finalizing them" do
      expect { terminate_service.call }.not_to have_enqueued_job(Invoices::FinalizeJob)

      expect(contract.reload).to be_canceled
      expect(invoices.map(&:reload)).to all(be_deleted)
    end
  end

  context "with draft invoices and a pending contract on the shadow organization of a paused migration" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization, status: "paused")
      contract
      invoices
    end

    it "cancels the contract and deletes the drafts instead of finalizing them" do
      expect { terminate_service.call }.not_to have_enqueued_job(Invoices::FinalizeJob)

      expect(contract.reload).to be_canceled
      expect(invoices.map(&:reload)).to all(be_deleted)
    end
  end

  context "with contracts on the shadow organization of a shadowing migration" do
    let(:active_contract) { create(:contract, customer:) }
    let(:terminated_contract) { create(:contract, :terminated, customer:, terminated_at: 2.days.ago) }
    let(:canceled_contract) { create(:contract, :canceled, customer:, canceled_at: 3.days.ago) }
    let(:draft_contract) { create(:contract, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization, status: "shadowing")
      active_contract
      terminated_contract
      canceled_contract
      draft_contract
    end

    it "cancels the draft contract" do
      freeze_time do
        expect { terminate_service.call }
          .to change { draft_contract.reload.status }.from("draft").to("canceled")
          .and change(draft_contract, :canceled_at).from(nil).to(Time.current)
      end
    end

    it "terminates the active contract and leaves ended contracts alone" do
      freeze_time do
        expect { terminate_service.call }
          .to change { active_contract.reload.status }.from("active").to("terminated")
          .and change(active_contract, :terminated_at).from(nil).to(Time.current)
          .and not_change { terminated_contract.reload.attributes.slice("status", "terminated_at", "canceled_at") }
          .and not_change { canceled_contract.reload.attributes.slice("status", "terminated_at", "canceled_at") }
      end
    end
  end

  context "with a live contract and draft invoices on the shadow organization of a migration" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }
    let(:calls) { [] }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)
      contract
      invoices

      allow(Contracts::TerminateService).to receive(:call!).and_wrap_original do |original, **kwargs|
        calls << [:contract, kwargs[:contract].id]
        original.call(**kwargs)
      end
      allow(Invoices::DeleteService).to receive(:call).and_wrap_original do |original, **kwargs|
        calls << [:invoice, kwargs[:invoice].id]
        original.call(**kwargs)
      end
    end

    it "terminates the contract before deleting the first draft" do
      terminate_service.call

      expect(calls.map(&:first)).to eq([:contract, :invoice, :invoice])
      expect(calls.first).to eq([:contract, contract.id])
      expect(calls.drop(1).map(&:last)).to match_array(invoices.map(&:id))
    end
  end

  context "with a live contract whose termination fails on the shadow organization of a migration" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)
      contract
      invoices

      allow(Contracts::TerminateService).to receive(:call!)
        .and_raise(BaseService::LockAcquisitionFailure.new(nil, code: "lock_acquisition_failed", error_message: "Failed to acquire lock"))
    end

    it "raises and keeps the drafts for the retry" do
      expect { terminate_service.call }
        .to raise_error(BaseService::LockAcquisitionFailure)
        .and not_have_enqueued_job(Invoices::FinalizeJob)

      expect(invoices.map(&:reload)).to all(be_draft)
    end
  end

  context "with draft invoices on the shadow organization of a migration" do
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)
      invoices

      allow(Customers::LockService).to receive(:call!).and_call_original
    end

    it "deletes the drafts under the customer billing-schedule lock" do
      terminate_service.call

      expect(Customers::LockService).to have_received(:call!).with(customer:, scope: :billing_schedule, transaction: false)
      expect(invoices.map(&:reload)).to all(be_deleted)
    end

    context "when a billing run holds the lock" do
      before do
        allow(Customers::LockService).to receive(:call!).and_raise(BaseLockService::FailedToAcquireLock, "Failed to acquire lock")
      end

      it "raises and keeps the drafts for the retry" do
        expect { terminate_service.call }.to raise_error(BaseLockService::FailedToAcquireLock)

        expect(invoices.map(&:reload)).to all(be_draft)
      end
    end
  end

  context "with a draft invoice the deletion refuses on the shadow organization of a migration" do
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }
    let(:refused_invoice) { invoices.first }
    let(:deleted_invoice) { invoices.last }

    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization)

      allow(Invoices::DeleteService).to receive(:call).and_call_original
      allow(Invoices::DeleteService).to receive(:call).with(invoice: refused_invoice).and_return(
        Invoices::DeleteService::Result.new.not_allowed_failure!(code: "invoice_synced_to_external_system")
      )
      allow(Rails.logger).to receive(:warn).and_call_original
    end

    it "logs the refused draft and deletes the others without finalizing any" do
      result = nil

      expect { result = terminate_service.call }.not_to have_enqueued_job(Invoices::FinalizeJob)

      expect(result).to be_success
      expect(refused_invoice.reload).to be_draft
      expect(deleted_invoice.reload).to be_deleted
      expect(Rails.logger).to have_received(:warn).with(include(refused_invoice.id, "invoice_synced_to_external_system"))
    end
  end

  shared_examples "finalizing drafts and leaving contracts untouched" do
    let(:contract) { create(:contract, :pending, customer:) }
    let(:invoices) { create_list(:invoice, 2, :draft, customer:) }

    before do
      contract
      invoices
    end

    it "enqueues finalize jobs 5 minutes later and leaves the contract and drafts as they are" do
      freeze_time do
        expect { terminate_service.call }
          .to have_enqueued_job(Invoices::FinalizeJob).at(5.minutes.from_now).exactly(:twice)
      end

      expect(contract.reload).to be_pending
      expect(invoices.map(&:reload)).to all(be_draft)
    end
  end

  context "with draft invoices and a pending contract on an organization without a migration" do
    it_behaves_like "finalizing drafts and leaving contracts untouched"
  end

  context "with draft invoices and a pending contract on the shadow organization of an aborted migration" do
    before do
      create(:billing_engine_migration, organization: create(:organization), shadow_organization: customer.organization, status: "aborted")
    end

    it_behaves_like "finalizing drafts and leaving contracts untouched"
  end

  context "with draft invoices and a pending contract on the source organization of a migration" do
    before { create(:billing_engine_migration, organization: customer.organization) }

    it_behaves_like "finalizing drafts and leaving contracts untouched"
  end

  context "with an applied coupon" do
    let(:applied_coupon) { create(:applied_coupon, customer:) }

    before { applied_coupon }

    it "terminates the applied coupon" do
      terminate_service.call

      expect(applied_coupon.reload).to be_terminated
    end
  end

  context "with an active wallet" do
    let(:wallet) { create(:wallet, customer:) }

    before { wallet }

    it "terminates the wallet" do
      terminate_service.call

      expect(wallet.reload).to be_terminated
    end
  end
end
