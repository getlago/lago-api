# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::DeleteService do
  subject(:delete_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :draft, organization:, customer:) }

  describe "#call" do
    it "marks the invoice as deleted" do
      result = delete_service.call

      expect(result).to be_success
      expect(result.invoice).to be_deleted
      expect(invoice.reload).to be_deleted
    end

    it "enqueues the invoice.deleted webhook" do
      expect { delete_service.call }
        .to have_enqueued_job(SendWebhookJob).with("invoice.deleted", invoice)
    end

    it "produces an activity log" do
      invoice = described_class.call(invoice:).invoice

      expect(Utils::ActivityLog).to have_produced("invoice.deleted").after_commit.with(invoice)
    end

    context "when invoice is nil" do
      let(:invoice) { nil }

      it "returns a not found failure" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("invoice")
      end
    end

    context "when invoice is not a draft" do
      let(:invoice) { create(:invoice, status: :finalized, organization:, customer:) }

      it "returns a not allowed failure and does not delete the invoice" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("not_deletable")
        expect(invoice.reload).to be_finalized
      end

      it "does not enqueue a webhook" do
        expect { delete_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when the invoice has been synced externally" do
      before { create(:integration_resource, syncable: invoice) }

      it "returns a not allowed failure and does not delete the invoice" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("invoice_synced_to_external_system")
        expect(invoice.reload).to be_draft
      end
    end

    context "when the draft invoice has a credit note" do
      let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

      before { credit_note }

      it "marks the credit note as deleted alongside the invoice" do
        result = delete_service.call

        expect(result).to be_success
        expect(invoice.reload).to be_deleted
        expect(credit_note.reload).to be_deleted
      end
    end

    context "when the draft invoice has a credit note that cannot be deleted" do
      let(:credit_note) { create(:credit_note, status: :finalized, invoice:, customer:) }

      before { credit_note }

      it "returns a failure and does not delete the invoice or the credit note" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("credit_note_not_deletable")
        expect(invoice.reload).to be_draft
        expect(credit_note.reload).to be_finalized
      end

      it "does not enqueue a webhook" do
        expect { delete_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when the draft invoice has several credit notes and one cannot be deleted" do
      let(:deletable_credit_note) { create(:credit_note, :draft, invoice:, customer:, created_at: 2.days.ago) }
      let(:blocking_credit_note) { create(:credit_note, status: :finalized, invoice:, customer:, created_at: 1.day.ago) }
      let(:other_invoice) { create(:invoice, :draft, organization:, customer:) }

      before do
        deletable_credit_note
        blocking_credit_note
      end

      it "leaves every credit note and the invoice untouched" do
        result = delete_service.call

        expect(result).not_to be_success
        expect(invoice.reload).to be_draft
        expect(deletable_credit_note.reload).to be_draft
        expect(blocking_credit_note.reload).to be_finalized
      end

      it "does not enqueue a webhook" do
        expect { delete_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end

      it "rolls back its own changes without affecting the surrounding transaction" do
        ActiveRecord::Base.transaction do
          other_invoice.update!(payment_overdue: true)
          delete_service.call
        end

        # the surrounding transaction's change is kept...
        expect(other_invoice.reload.payment_overdue).to be(true)
        # ...while the service's own cascade was rolled back
        expect(invoice.reload).to be_draft
        expect(deletable_credit_note.reload).to be_draft
      end
    end
  end
end
