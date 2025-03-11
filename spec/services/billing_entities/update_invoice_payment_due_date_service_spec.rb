# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::UpdateInvoicePaymentDueDateService, type: :service do
  subject(:update_service) { described_class.new(billing_entity:, net_payment_term:) }

  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:customer) { create(:customer, organization:, net_payment_term: customer_net_payment_term) }
  let(:customer_net_payment_term) { nil }
  let(:net_payment_term) { 30 }

  describe "#call" do
    it "updates invoice payment_due_date" do
      result = update_service.call
      expect(result.billing_entity.net_payment_term).to eq(30)
    end

    # TODO: uncomment when we start updating invoices
    # let(:draft_invoice) do
    #   create(:invoice, status: :draft, customer:, organization:, issuing_date: DateTime.parse("21 Jun 2022"), billing_entity:)
    # end
    #
    # before do
    #   draft_invoice
    # end
    #
    # it "updates invoice payment_due_date" do
    #   expect { update_service.call }.to change { draft_invoice.reload.payment_due_date }
    #     .from(DateTime.parse("21 Jun 2022"))
    #     .to(DateTime.parse("21 Jun 2022") + net_payment_term.days)
    # end
    #
    # it "updates invoice net_payment_date" do
    #   expect { update_service.call }.to change { draft_invoice.reload.net_payment_term }
    #     .from(0).to(30)
    # end
    #
    # context "when customer has their own net_payment_term" do
    #   let(:customer_net_payment_term) { 10 }
    #
    #   it "doesn't update fields" do
    #     expect { update_service.call }.not_to change { draft_invoice.reload.payment_due_date }
    #     expect { update_service.call }.not_to change { draft_invoice.reload.net_payment_term }
    #   end
    # end
  end
end
