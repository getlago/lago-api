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
