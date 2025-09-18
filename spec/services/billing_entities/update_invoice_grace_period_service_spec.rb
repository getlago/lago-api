# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::UpdateInvoiceGracePeriodService do
  include ActiveJob::TestHelper

  subject(:update_service) { described_class.new(billing_entity:, grace_period:) }

  let(:billing_entity) { create(:billing_entity, invoice_grace_period: 9) }
  let(:organization) { billing_entity.organization }
  let(:customer) { create(:customer, organization:, net_payment_term: 5) }
  let(:grace_period) { 15 }

  describe "#call" do
    let(:invoice_draft) do
      create(
        :invoice,
        customer:,
        billing_entity:,
        status: :draft,
        issuing_date: DateTime.parse("19 Jun 2022").to_date,
        applied_grace_period: 9
      )
    end

    before do
      invoice_draft
    end

    it "updates invoice grace period on billing_entity" do
      expect { update_service.call }
        .to change { billing_entity.reload.invoice_grace_period }.from(9).to(15)
    end

    it "updates issuing_date and payment_due_date on draft invoices" do
      expect { perform_enqueued_jobs { update_service.call } }
        .to change { invoice_draft.reload.issuing_date }.to(DateTime.parse("25 Jun 2022"))
        .and change { invoice_draft.reload.payment_due_date }.to(DateTime.parse("30 Jun 2022"))
    end

    context "when grace_period is the same as the current one on the billing_entity" do
      let(:grace_period) { billing_entity.invoice_grace_period }

      it "does not update issuing_date on draft invoices" do
        expect { update_service.call }.not_to change { invoice_draft.reload.issuing_date }
      end
    end
  end
end
